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

RUN npm install \
 && npm run build


################################################
# Backend Base (FFmpeg + VAAPI + PyAV)
################################################
FROM python:3.12-slim AS backend-base

ARG PIP_INDEX_URL
ENV TZ=Asia/Shanghai
ENV DEBIAN_FRONTEND=noninteractive

# 强制使用 Intel iHD VAAPI 驱动
ENV LIBVA_DRIVER_NAME=iHD

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
 && echo $TZ > /etc/timezone

WORKDIR /app

# ================================
# System dependencies
# ================================
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    # --- build tools ---
    build-essential \
    pkg-config \
    python3-dev \
    # --- FFmpeg (VAAPI enabled) ---
    ffmpeg \
    libavcodec-dev \
    libavformat-dev \
    libavdevice-dev \
    libavutil-dev \
    libavfilter-dev \
    libswscale-dev \
    libswresample-dev \
    # --- Intel VAAPI ---
    intel-media-va-driver \
    libva2 \
    libva-drm2 \
    libva-x11-2 \
    libva-wayland2 \
    libva-glx2 \
    vainfo \
 && rm -rf /var/lib/apt/lists/*

# ================================
# Python dependencies (PyAV)
# ================================
RUN pip config set global.index-url "${PIP_INDEX_URL}" \
 && pip install --upgrade pip setuptools wheel \
 && pip install --no-cache-dir av


# ================================
# Install project dependencies
# ================================
COPY miloco_server/pyproject.toml /app/miloco_server/pyproject.toml
COPY miot_kit/pyproject.toml /app/miot_kit/pyproject.toml

RUN pip install --no-build-isolation /app/miloco_server \
 && pip install --no-build-isolation /app/miot_kit \
 && rm -rf /root/.cache/pip \
 && rm -rf /app/miloco_server \
 && rm -rf /app/miot_kit


################################################
# Backend Runtime
################################################
FROM backend-base AS backend

WORKDIR /app

# Copy backend source
COPY miloco_server /app/miloco_server
COPY miot_kit /app/miot_kit
COPY scripts/start_server.py /app/start_server.py
COPY config/server_config.yaml /app/config/server_config.yaml
COPY config/prompt_config.yaml /app/config/prompt_config.yaml

# Editable install (runtime)
RUN pip install --no-build-isolation -e /app/miloco_server \
 && pip install --no-build-isolation -e /app/miot_kit \
 && rm -rf /root/.cache/pip \
 && rm -rf /app/miloco_server/static \
 && rm -rf /app/miloco_server/.temp \
 && rm -rf /app/miloco_server/.log

# Copy frontend build
COPY --from=frontend-builder /app/dist/ /app/miloco_server/static/

EXPOSE 8000

CMD ["python3", "start_server.py"]