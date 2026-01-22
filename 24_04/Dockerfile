FROM ubuntu:24.04 AS install

RUN apt update \
    && apt install -y build-essential \
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
# libvtk7-dev
# libvtk7-qt-dev
# qt5-default

RUN git clone https://github.com/uos/lvr2.git
RUN mkdir lvr2/build \
    && cd lvr2/build \
    && cmake .. \
    && make -j

FROM ubuntu:24.04 AS binary
WORKDIR /lvr2

RUN apt update \
    && apt install -y \
    libboost-program-options1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-iostreams1.83.0 \
    libembree4-4 \
    libglu1 \
    libgomp1 \
    libgslcblas0 \
    libhdf5-dev \
    libopencv-imgcodecs406t64 \
    libopencv-features2d406t64 \
    libyaml-cpp0.8

COPY --from=install [ \
    "/lvr2/build/bin/lvr2_hdf5_mesh_tool", \
    "/lvr2/build/bin/lvr2_mesh_reduce", \
    "/lvr2/build/bin/lvr2_reconstruct", \
    "/lvr2/" \
    ]
