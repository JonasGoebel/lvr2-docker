FROM ubuntu:20.04 AS install

RUN apt update \
    && DEBIAN_FRONTEND=noninteractive apt install -y build-essential \
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

RUN git clone https://github.com/uos/lvr2.git
RUN mkdir lvr2/build \
    && cd lvr2/build \
    && cmake .. \
    && make -j

FROM ubuntu:20.04 AS binary
WORKDIR /lvr2

RUN apt update \
    && DEBIAN_FRONTEND=noninteractive apt install -y \
    libboost-program-options1.71.0 \
    libboost-filesystem1.71.0 \
    libboost-iostreams1.71.0 \
    libembree3-3 \
    libglu1 \
    libgomp1 \
    libgslcblas0 \
    libhdf5-dev \
    libopencv-imgcodecs4.2 \
    libopencv-features2d4.2 \
    libopengl0 \
    libyaml-cpp0.6

COPY --from=install [ \
    "/lvr2/build/bin/lvr2_hdf5_mesh_tool", \
    "/lvr2/build/bin/lvr2_mesh_reduce", \
    "/lvr2/build/bin/lvr2_reconstruct", \
    "/lvr2/" \
    ]
