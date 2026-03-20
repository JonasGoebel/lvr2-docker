##############################################################################
# Stage 0: PDAL (sourced from the official pdal/pdal image)
##############################################################################
FROM pdal/pdal:latest AS pdal

##############################################################################
# Stage 1: build
##############################################################################
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

# --- Clone lvr2 source ------------------------------------------------------
RUN git clone https://github.com/uos/lvr2.git /lvr2

# --- Apply patches -----------------------------------------------------------
#
# All patches fix bugs that prevent the project from building with
# -DLVR2_WITH_CUDA=ON + -DLVR2_WITH_3DTILES=ON on Ubuntu 24.04 / GCC 13.
# They are kept as targeted in-place edits so the diff against upstream is
# minimal and easy to audit.

# Note: upstream CMakeLists.txt uses LVR2_WITH_3DTILES, LVR2_WITH_CUDA,
# LVR2_BUILD_TOOLS etc. (all with the LVR2_ prefix) as the user-facing cmake
# option names.  The cmake configure command below passes those correct names.
# The sub-directory src/liblvr2/CMakeLists.txt uses the unprefixed WITH_3DTILES;
# Patch 5 bridges the two by injecting set(WITH_3DTILES ${LVR2_WITH_3DTILES})
# in the root CMakeLists.txt before add_subdirectory(src/liblvr2).

# Patch 2 (CMakeLists.txt):
#   Replace the original single-line CMAKE_CXX_FLAGS with flags that also
#   force-include <cstdint> (the bundled Draco omits it, which is an error
#   under GCC 13) and suppress -Werror (Cesium's own -Werror trips on
#   false-positive warnings in PicoSHA2 under GCC 13).
#   Also add CMAKE_C_FLAGS=-fPIC so libsqlite3.a can be linked into a shared
#   library (the original flag was C++ only).
RUN sed -i \
    's|-DCMAKE_CXX_FLAGS=-fPIC           # tell cmake to compile as shared libraries|"-DCMAKE_CXX_FLAGS=-fPIC -include cstdint -Wno-error"\n        "-DCMAKE_C_FLAGS=-fPIC"|' \
    /lvr2/CMakeLists.txt

# Patch 3 (CMakeLists.txt):
#   Remove -Werror from cesium-native's configure step via PATCH_COMMAND so
#   GCC 13 warnings in bundled third-party code (PicoSHA2, Draco) do not
#   abort the build.  This runs after the git clone of cesium-native.
RUN python3 - <<'PYEOF'
import pathlib

path = pathlib.Path('/lvr2/CMakeLists.txt')
text = path.read_text()

old = '    LOG_CONFIGURE ON\n    LOG_INSTALL ON'
new = ('    PATCH_COMMAND sed -i "s/-Werror -Wall/-Wall/g" <SOURCE_DIR>/CMakeLists.txt\n'
       '    LOG_CONFIGURE ON\n    LOG_INSTALL ON')
assert old in text, 'Patch 3: LOG_CONFIGURE ON not found after GIT_TAG block'
path.write_text(text.replace(old, new, 1))
print('Patch 3 applied')
PYEOF

# Patch 4 (CMakeLists.txt):
#   3DTILES_FOUND was never set, so the Cesium libraries were never appended
#   to LVR2_LIB_DEPENDENCIES.  Also expand the library list to include all
#   transitive cesium-native static dependencies.
RUN python3 - <<'PYEOF'
import re, pathlib

path = pathlib.Path('/lvr2/CMakeLists.txt')
text = path.read_text()

old = ('  set(3DTILES_LIBRARIES Cesium3DTiles Cesium3DTilesWriter '
       'CesiumGltf CesiumGltfWriter CesiumJsonWriter)')
new = (
    '  set(3DTILES_LIBRARIES\n'
    '    Cesium3DTiles Cesium3DTilesWriter Cesium3DTilesReader Cesium3DTilesSelection\n'
    '    CesiumGltf CesiumGltfWriter CesiumGltfReader\n'
    '    CesiumJsonWriter CesiumJsonReader\n'
    '    CesiumAsync CesiumGeometry CesiumGeospatial CesiumUtility CesiumIonClient\n'
    '    async++ uriparser tinyxml2 sqlite3 modp_b64 csprng ktx_read s2geometry)\n'
    '  set(3DTILES_FOUND ON)'
)
assert old in text, 'Patch 4: target string not found'
path.write_text(text.replace(old, new, 1))
print('Patch 4 applied')
PYEOF

# Patch 5 (CMakeLists.txt + src/liblvr2/CMakeLists.txt):
#   cmake ExternalProject_Add() creates a custom target that must be referenced
#   via add_dependencies() only AFTER all participant targets exist in the same
#   cmake directory scope.  The upstream source places add_dependencies(lvr2core
#   cesium-native) inside src/liblvr2/CMakeLists.txt (a subdirectory), which
#   causes cmake to report "dependency target 'cesium-native' does not exist"
#   even though ExternalProject_Add() is called earlier in the root CMakeLists.txt.
#
#   Fix: remove the add_dependencies call from the subdirectory CMakeLists.txt
#   and instead inject both add_dependencies calls into the ROOT CMakeLists.txt
#   immediately after add_subdirectory(src/liblvr2) — at that point all three
#   targets (cesium-native, lvr2core, lvr2) are guaranteed to exist.
RUN python3 - <<'PYEOF'
import pathlib

# Step A: remove the add_dependencies(lvr2core cesium-native) that upstream
# placed inside src/liblvr2/CMakeLists.txt.
sub_path = pathlib.Path('/lvr2/src/liblvr2/CMakeLists.txt')
sub_text = sub_path.read_text()

old_sub = (
    'if(WITH_3DTILES)\n'
    '    add_dependencies(lvr2core cesium-native)\n'
    'endif(WITH_3DTILES)'
)
assert old_sub in sub_text, 'Patch 5A: upstream add_dependencies block not found'
sub_path.write_text(sub_text.replace(old_sub, '# (dependency moved to root CMakeLists.txt by Patch 5)', 1))
print('Patch 5A applied: removed add_dependencies from subdir')

# Step B: inject add_dependencies for both lvr2core and lvr2 into the ROOT
# CMakeLists.txt, right after add_subdirectory(src/liblvr2).
root_path = pathlib.Path('/lvr2/CMakeLists.txt')
root_text = root_path.read_text()

old_root = 'add_subdirectory(src/liblvr2)'
new_root = (
    '# Patch 5: bridge LVR2_WITH_3DTILES -> WITH_3DTILES so the subdirectory\n'
    '# CMakeLists.txt (which tests if(WITH_3DTILES)) picks up the flag.\n'
    'set(WITH_3DTILES ${LVR2_WITH_3DTILES})\n'
    '\n'
    'add_subdirectory(src/liblvr2)\n'
    '\n'
    '# Patch 5: wire cesium-native ExternalProject into the lvr2 build targets.\n'
    '# Must be done here (root scope, after add_subdirectory) so that all three\n'
    '# targets — cesium-native, lvr2core, and lvr2 — are already defined.\n'
    'if(LVR2_WITH_3DTILES)\n'
    '    add_dependencies(lvr2core cesium-native)\n'
    '    add_dependencies(lvr2 cesium-native)\n'
    'endif(LVR2_WITH_3DTILES)'
)
assert old_root in root_text, 'Patch 5B: add_subdirectory(src/liblvr2) not found in root CMakeLists.txt'
root_path.write_text(root_text.replace(old_root, new_root, 1))
print('Patch 5B applied: injected add_dependencies into root CMakeLists.txt')
PYEOF

# Patch 6 (include/lvr2/algorithm/ChunkingPipeline.tcc):
#   Pre-existing API mismatch: calcVertexHeightDifferences() requires three
#   arguments (mesh, normals, radius) but the caller passes only two.
RUN sed -i \
    's|calcVertexHeightDifferences(hem, m_heightDifferencesRadius)|calcVertexHeightDifferences(hem, vertexNormals, m_heightDifferencesRadius)|' \
    /lvr2/include/lvr2/algorithm/ChunkingPipeline.tcc

# Patch 7 (CMakeLists.txt):
#   Cesium-native installs its own older spdlog (fmt v8) into its install/include
#   directory. Because both spdlog versions ship headers under the same path
#   (spdlog/fmt/bundled/core.h etc.), one version's headers pull in the other
#   version's headers via the include search path, causing ODR / redefinition
#   errors when compiling lvr2 source files like util/Logging.cpp.
#
#   Fix: add an ExternalProject step (via ExternalProject_Add_Step) that removes
#   the conflicting spdlog directory from cesium-native's install tree right
#   after its install step.  This leaves cesium-native's own translation units
#   unaffected (they are already compiled by the time we strip the headers) and
#   prevents the old headers from polluting the lvr2 compile.
RUN python3 - <<'PYEOF'
import pathlib

path = pathlib.Path('/lvr2/CMakeLists.txt')
text = path.read_text()

# Insert an ExternalProject_Add_Step that strips spdlog from cesium's install,
# right after the ExternalProject_Get_Property(cesium-native SOURCE_DIR) line.
old = ('  ExternalProject_Get_Property(cesium-native SOURCE_DIR)\n'
       '  include_directories(${SOURCE_DIR}/extern/draco/src')
new = ('  ExternalProject_Get_Property(cesium-native SOURCE_DIR)\n'
       '  # Patch 7: remove cesium-native\'s bundled spdlog from its install tree\n'
       '  # to prevent it from shadowing lvr2\'s own (newer) spdlog headers.\n'
       '  ExternalProject_Add_Step(cesium-native strip-spdlog\n'
       '    COMMAND ${CMAKE_COMMAND} -E remove_directory\n'
       '            ${BINARY_DIR}/install/include/spdlog\n'
       '    DEPENDEES install\n'
       '    ALWAYS FALSE\n'
       '  )\n'
       '  include_directories(${SOURCE_DIR}/extern/draco/src')
assert old in text, 'Patch 7: ExternalProject_Get_Property(SOURCE_DIR) line not found'
path.write_text(text.replace(old, new, 1))
print('Patch 7 applied: added strip-spdlog step to cesium-native ExternalProject')
PYEOF

# --- Configure --------------------------------------------------------------
RUN cmake \
    -S /lvr2 \
    -B /lvr2/build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLVR2_WITH_CUDA=ON \
    -DLVR2_WITH_3DTILES=ON \
    -DLVR2_BUILD_TOOLS=ON \
    -DLVR2_BUILD_TOOLS_EXPERIMENTAL=ON \
    -DCMAKE_CUDA_ARCHITECTURES=native

# --- Build ------------------------------------------------------------------
RUN cmake --build /lvr2/build -- -j$(nproc)

##############################################################################
# Stage 2: minimal runtime image
##############################################################################
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# --- Add NVIDIA repo for CUDA runtime packages ------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL \
    https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    -o /tmp/cuda-keyring.deb \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm /tmp/cuda-keyring.deb \
    && rm -rf /var/lib/apt/lists/*

# --- Runtime libraries ------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    \
    `# CUDA runtime (cudart + nvrtc needed by lvr2cuda)` \
    cuda-cudart-12-8 \
    cuda-nvrtc-12-8 \
    \
    `# Boost runtime` \
    libboost-atomic1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-iostreams1.83.0 \
    libboost-program-options1.83.0 \
    libboost-serialization1.83.0 \
    libboost-thread1.83.0 \
    \
    `# OpenCV runtime` \
    libopencv-calib3d406t64 \
    libopencv-core406t64 \
    libopencv-features2d406t64 \
    libopencv-flann406t64 \
    libopencv-imgcodecs406t64 \
    libopencv-imgproc406t64 \
    \
    `# HDF5 runtime` \
    libhdf5-103-1t64 \
    libhdf5-hl-100t64 \
    \
    `# Geometry / math / raytracing` \
    libembree4-4 \
    libgsl27 \
    libgslcblas0 \
    libtbb12 \
    \
    `# Geospatial` \
    libgdal34t64 \
    \
    `# I/O` \
    liblz4-1 \
    libtiff6 \
    libyaml-cpp0.8 \
    \
    `# OpenGL / display` \
    libglu1-mesa \
    libglut3.12 \
    libopengl0 \
    \
    `# Compute: OpenCL, MPI, OpenMP` \
    ocl-icd-libopencl1 \
    libopenmpi3t64 \
    libgomp1 \
    \
    && rm -rf /var/lib/apt/lists/*

# Make the CUDA runtime libraries findable
ENV PATH=/usr/local/cuda-12.8/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64

WORKDIR /lvr2

# --- Copy built binaries and shared libraries from the build stage ----------
COPY --from=build /lvr2/build/bin/ /lvr2/bin/
COPY --from=build /lvr2/build/lib/ /lvr2/lib/

# Make the lvr2 shared libraries findable at runtime
ENV LD_LIBRARY_PATH=/lvr2/lib:$LD_LIBRARY_PATH

# --- PDAL (copied from official pdal/pdal image) ----------------------------
# The pdal binary and all its conda-bundled shared libraries are self-contained
# under /opt/conda/envs/pdal in the source image.  We copy them verbatim so
# that no additional apt packages are needed.
COPY --from=pdal /opt/conda/envs/pdal/bin/pdal      /opt/pdal/bin/pdal
COPY --from=pdal /opt/conda/envs/pdal/bin/pdal-config /opt/pdal/bin/pdal-config
COPY --from=pdal /opt/conda/envs/pdal/lib/          /opt/pdal/lib/

ENV PATH=/opt/pdal/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/pdal/lib:$LD_LIBRARY_PATH
