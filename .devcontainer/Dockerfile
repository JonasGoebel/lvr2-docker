FROM ubuntu:24.04 AS build

ENV DEBIAN_FRONTEND=noninteractive

# --- Base build tools and all lvr2 compile-time dependencies ----------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ninja-build \
    git \
    curl \
    ca-certificates \
    cmake \
    cmake-curses-gui \
    libflann-dev \
    libgsl-dev \
    libeigen3-dev \
    libopenmpi-dev \
    openmpi-bin \
    opencl-c-headers \
    ocl-icd-opencl-dev \
    libboost-all-dev \
    freeglut3-dev \
    libhdf5-dev \
    qtbase5-dev \
    libqt5opengl5-dev \
    liblz4-dev \
    libopencv-dev \
    libyaml-cpp-dev \
    libembree-dev \
    libgdal-dev \
    libtiff-dev \
    libtbb-dev \
    libvtk9-dev \
    libvtk9-qt-dev \
    && rm -rf /var/lib/apt/lists/*

# --- CUDA 12.8 toolkit (compiler + dev libraries) ---------------------------
# The NVIDIA driver is provided by the host at runtime via the container
# runtime (--gpus all / nvidia-container-toolkit). Only the toolkit (nvcc,
# headers, static stubs) is needed at build time.
RUN curl -fsSL \
    https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    -o /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y --no-install-recommends \
    cuda-compiler-12-8 \
    cuda-cudart-dev-12-8 \
    libcublas-dev-12-8 \
    libcusolver-dev-12-8 \
    cuda-nvrtc-dev-12-8 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/local/cuda-12.8/bin:$PATH

RUN curl -fsSL https://opencode.ai/install | bash

# --- Clone lvr2 source ------------------------------------------------------
RUN git clone https://github.com/uos/lvr2.git /lvr2
