# syntax=docker/dockerfile:1.4
# Set pip index URL.
# For Worldwide: 
# - https://pypi.org/simple/
# For China: 
# - https://mirrors.aliyun.com/pypi/simple/
# - https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
#ARG PIP_INDEX_URL=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
ARG PIP_INDEX_URL=https://pypi.org/simple

################################################
# Frontend Builder
################################################
FROM node:20-slim AS frontend-builder

WORKDIR /app
COPY web_ui/ /app/

RUN npm install
RUN npm run build


################################################
# FFmpeg Builder with VAAPI
################################################
FROM --platform=linux/amd64 ubuntu:22.04 AS ffmpeg-builder

# Install build dependencies
RUN apt-get update && \
    [ -f /etc/apt/sources.list.d/ubuntu.sources ] && sed -i 's/Components: main restricted/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources || true && \
    [ -f /etc/apt/sources.list ] && sed -i 's/main/main restricted universe multiverse/g' /etc/apt/sources.list || true && \
    \
    apt-get update && apt-get install -y \
    wget \
    tar \
    git \
    make \
    gcc \
    g++ \
    yasm \
    pkg-config \
    nasm \
    libdrm-dev \
    libva-dev \
    libx264-dev \
    libx265-dev \
    intel-media-va-driver \
    && rm -rf /var/lib/apt/lists/*

# Set FFmpeg version
ARG FFMPEG_VERSION=6.1.1

# Download and build FFmpeg with VAAPI
WORKDIR /build
RUN wget "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && tar -xf "ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && rm "ffmpeg-${FFMPEG_VERSION}.tar.xz"

WORKDIR /build/ffmpeg-${FFMPEG_VERSION}

RUN ./configure \
    --prefix=/usr/local \
    --enable-shared \
    --disable-static \
    --enable-gpl \
    --enable-version3 \
    --disable-nonfree \
    --enable-vaapi \
    --enable-libdrm \
    --enable-hwaccel=h264_vaapi \
    --enable-hwaccel=hevc_vaapi \
    --enable-hwaccel=mjpeg_vaapi \
    --enable-hwaccel=mpeg2_vaapi \
    --enable-hwaccel=vp8_vaapi \
    --enable-hwaccel=vp9_vaapi \
    --enable-libx264 \
    --enable-libx265 \
    --disable-doc \
    --disable-debug \
    --enable-pic

RUN make -j$(nproc) \
    && make install \
    && ldconfig


################################################
# PyAV Builder with VAAPI Support
################################################
FROM ffmpeg-builder AS pyav-builder

# Install Python 3.12 and build dependencies (matching backend-base)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    gnupg \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    python3-pip \
    python3-dev \
    cython3 \
    python3-numpy \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Use Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3-dev python3-dev /usr/bin/python3.12-dev 1

# Clone and build PyAV from source
WORKDIR /build
RUN git clone https://github.com/PyAV-Org/PyAV.git

WORKDIR /build/PyAV
RUN python3 setup.py build_ext --no-config
RUN python3 setup.py install


################################################
# Backend Base
################################################
FROM python:3.12-slim AS backend-base

# Restate PIP index URL.
ARG PIP_INDEX_URL

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install runtime dependencies including VAAPI
RUN apt-get update && \    
    [ -f /etc/apt/sources.list.d/ubuntu.sources ] && sed -i 's/Components: main restricted/Components: main restricted universe multiverse/g' /etc/apt/sources.list.d/ubuntu.sources || true && \
    [ -f /etc/apt/sources.list ] && sed -i 's/main/main restricted universe multiverse/g' /etc/apt/sources.list || true && \
    \
    apt-get update && apt-get install -y \
    libva2 \
    libva-drm2 \
    intel-media-va-driver \
    && rm -rf /var/lib/apt/lists/*

# Copy FFmpeg and PyAV from builders
COPY --from=ffmpeg-builder /usr/local /usr/local
COPY --from=pyav-builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages

# Update library paths
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
ENV PYTHONPATH=/usr/local/lib/python3.12/site-packages:$PYTHONPATH

# Set working directory.
WORKDIR /app

# Copy app files.
COPY miloco_server/pyproject.toml /app/miloco_server/pyproject.toml
COPY miot_kit/pyproject.toml /app/miot_kit/pyproject.toml

# Install dependencies
RUN pip config set global.index-url "${PIP_INDEX_URL}" \
    && pip install --upgrade pip setuptools wheel \
    && pip install --no-build-isolation /app/miloco_server \
    && pip install --no-build-isolation /app/miot_kit \
    && rm -rf /app/miloco_server \
    && rm -rf /app/miot_kit


################################################
# Backend
################################################
FROM backend-base AS backend

# Set working directory.
WORKDIR /app

# Copy app files.
COPY miloco_server /app/miloco_server
COPY config/server_config.yaml /app/config/server_config.yaml
COPY config/prompt_config.yaml /app/config/prompt_config.yaml
COPY scripts/start_server.py /app/start_server.py
COPY miot_kit /app/miot_kit

# Install project.
RUN pip install --no-build-isolation -e /app/miloco_server \
    && pip install --no-build-isolation -e /app/miot_kit \
    && rm -rf /app/miloco_server/static \
    && rm -rf /app/miloco_server/.temp \
    && rm -rf /app/miloco_server/.log

# Update frontend dist.
COPY --from=frontend-builder /app/dist/ /app/miloco_server/static/

EXPOSE 8000

# Override by docker-compose, this is the default command.
# HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD curl -f "https://127.0.0.1:8000" || exit 1

# Start application
CMD ["python3", "start_server.py"]
