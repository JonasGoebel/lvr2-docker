FROM ubuntu:24.04 AS install

RUN apt update \
    && apt install -y build-essential \
    curl \
    git \
    cmake cmake-curses-gui libflann-dev \
    libgsl-dev libeigen3-dev libopenmpi-dev \
    openmpi-bin opencl-c-headers ocl-icd-opencl-dev \
    libboost-all-dev \
    freeglut3-dev libhdf5-dev qtbase5-dev \
    libqt5opengl5-dev liblz4-dev \
    libopencv-dev libyaml-cpp-dev \
    libembree-dev \
    libgdal-dev

# missing:
# libvtk7-dev       ->  libvtk9-dev
# libvtk7-qt-dev    ->  libvtk9-qt-dev
# qt5-default       -> qt6-base-dev?
RUN curl -fsSL https://opencode.ai/install | bash

RUN git clone https://github.com/uos/lvr2.git