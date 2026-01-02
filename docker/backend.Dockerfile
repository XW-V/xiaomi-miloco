# syntax=docker/dockerfile:1.4
ARG PIP_INDEX_URL=https://pypi.org/simple

################################################
# Frontend Builder
################################################
FROM node:20-slim AS frontend-builder
WORKDIR /app
COPY web_ui/package*.json ./
# 优化：先拷贝 package.json 利用缓存
RUN npm install
COPY web_ui/ /app/
RUN npm run build

################################################
# FFmpeg Builder with VAAPI
################################################
FROM --platform=linux/amd64 ubuntu:22.04 AS ffmpeg-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget tar git make gcc g++ yasm pkg-config nasm \
    libdrm-dev libva-dev libx264-dev libx265-dev \
    intel-media-va-driver \
    && rm -rf /var/lib/apt/lists/*

ARG FFMPEG_VERSION=6.1.1
WORKDIR /build
RUN wget "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && tar -xf "ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && cd ffmpeg-${FFMPEG_VERSION} \
    && ./configure \
    --prefix=/usr/local --enable-shared --disable-static --enable-gpl --enable-version3 \
    --disable-nonfree --enable-vaapi --enable-libdrm \
    --enable-hwaccel=h264_vaapi --enable-hwaccel=hevc_vaapi \
    --enable-libx264 --enable-libx265 \
    --disable-doc --disable-debug --enable-pic \
    && make -j$(nproc) \
    && make install

################################################
# PyAV Builder
################################################
FROM ffmpeg-builder AS pyav-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.12 python3.12-dev python3.12-venv python3-pip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 https://github.com/PyAV-Org/PyAV.git
WORKDIR /build/PyAV

# 关键修正：直接使用 python3.12 调用，并确保使用刚编译的 FFmpeg
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
RUN python3.12 -m pip install --upgrade pip setuptools wheel Cython numpy
RUN python3.12 setup.py build_ext --inplace --include-dirs=/usr/local/include --library-dirs=/usr/local/lib
RUN python3.12 setup.py install --prefix=/usr/local

################################################
# Backend Base (Final Image)
################################################
FROM python:3.12-slim AS backend-base
ARG PIP_INDEX_URL
ENV TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH \
    PYTHONPATH=/usr/local/lib/python3.12/site-packages:$PYTHONPATH

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装运行时必需的库
RUN apt-get update && apt-get install -y \
    libva2 libva-drm2 intel-media-va-driver libx264-163 libx265-199 \
    && rm -rf /var/lib/apt/lists/*

# 从 builder 拷贝编译好的 FFmpeg 动态库和 PyAV
COPY --from=ffmpeg-builder /usr/local/lib /usr/local/lib
COPY --from=ffmpeg-builder /usr/local/include /usr/local/include
COPY --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
# 拷贝 PyAV 到 site-packages
COPY --from=pyav-builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages

WORKDIR /app

# 提前拷贝依赖文件以利用层缓存
COPY miloco_server/pyproject.toml /app/miloco_server/
COPY miot_kit/pyproject.toml /app/miot_kit/

RUN pip config set global.index-url "${PIP_INDEX_URL}" \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --no-build-isolation /app/miloco_server /app/miot_kit

################################################
# Final Stage
################################################
FROM backend-base AS backend
WORKDIR /app

COPY miloco_server /app/miloco_server
COPY config /app/config
COPY scripts/start_server.py /app/start_server.py
COPY miot_kit /app/miot_kit
COPY --from=frontend-builder /app/dist/ /app/miloco_server/static/

# 以可编辑模式安装或直接安装
RUN pip install --no-build-isolation -e /app/miloco_server -e /app/miot_kit

EXPOSE 8000
CMD ["python3", "start_server.py"]
