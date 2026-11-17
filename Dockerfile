# #####################################
# ############ STAGE 1 ################
# #####################################

ARG VALHALLA_VERSION=3.9.2
ARG VALHALLA_COMMIT=a919bb6b64d61d12f79ea5466d5cf599a39714ad
# prime_server 0.13.1
ARG PRIME_SERVER_COMMIT=0d41876997760e22396075aeb7873bffcffd8786
# Parallelism for the Valhalla compile. Defaults to all cores (used by CI).
# Override for memory-constrained local builds, e.g. --build-arg MAKE_JOBS=2,
# since each heavy C++ translation unit can use ~1-2 GB and -j$(nproc) can OOM.
ARG MAKE_JOBS
FROM ubuntu:24.04
ARG VALHALLA_VERSION
ARG VALHALLA_COMMIT
ARG PRIME_SERVER_COMMIT
ARG MAKE_JOBS

# Install build dependencies: what the prime_server and Valhalla CMake builds
# look for, plus the toolchain and git to fetch the sources.
# NOTE: spatialite-bin is a build dependency, not only a runtime one: Valhalla's
# CMake fails without the spatialite and spatialite_tool executables.
# NOTE: no libgdal-dev. Valhalla's GeoTIFF support (isochrone raster output)
# uses libgeotiff and libtiff directly; nothing links GDAL.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    cmake \
    g++ \
    gcc \
    git \
    libboost-all-dev \
    libcurl4-openssl-dev \
    libczmq-dev \
    libexpat1-dev \
    libgeos++-dev \
    libgeos-dev \
    libgeotiff-dev \
    libluajit-5.1-dev \
    liblz4-dev \
    libspatialite-dev \
    libsqlite3-dev \
    libprotobuf-dev \
    libssl-dev \
    libzmq3-dev \
    make \
    pkgconf \
    protobuf-compiler \
    spatialite-bin \
    zlib1g-dev

# prime_server
RUN git clone https://github.com/kevinkreiser/prime_server.git && (cd prime_server && git checkout ${PRIME_SERVER_COMMIT} && git submodule update --init --recursive && mkdir -p build && cd build && cmake .. && make -j2 install) && rm -rf /prime_server

# valhalla
# NOTE: -ENABLE_SINGLE_FILES_WERROR=OFF because of https://github.com/valhalla/valhalla/issues/3157
# NOTE: -DENABLE_TESTS=OFF to skip test builds (not needed in production image)
RUN git clone https://github.com/valhalla/valhalla.git && (cd valhalla && git checkout ${VALHALLA_COMMIT} -b build && git submodule update --init --recursive && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_NODE_BINDINGS=OFF -DENABLE_PYTHON_BINDINGS=OFF -DENABLE_TESTS=OFF -DENABLE_SINGLE_FILES_WERROR=OFF && make -j"${MAKE_JOBS:-$(nproc)}" install) && rm -rf /valhalla

# #####################################
# ############ STAGE 2 ################
# #####################################

FROM ubuntu:24.04
ARG VALHALLA_VERSION
ARG VALHALLA_CONCURRENCY=1

# Copy ARG to ENV
ENV VALHALLA_VERSION=${VALHALLA_VERSION} \
    VALHALLA_CONCURRENCY=${VALHALLA_CONCURRENCY}

# Install run-time dependencies and utilities.
# NOTE: libprotobuf-lite32t64, not libprotobuf-dev: Valhalla is built against
# protobuf-lite, and the -dev package would only add unused headers and static
# libs to the runtime image.
RUN apt-get update && apt-get upgrade -y && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    libcurl4 \
    libluajit-5.1-2 \
    libprotobuf-lite32t64 \
    libzmq5 \
    libczmq4 \
    libsqlite3-mod-spatialite \
    libgeotiff5 \
    python3 \
    spatialite-bin \
    jo \
    jq \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy previous installs
COPY --from=0 /usr/local /usr/local

# COPY doesn't refresh the linker cache, so the libraries just copied into
# /usr/local/lib (already on the default search path) wouldn't be found.
RUN ldconfig

# Setup
WORKDIR /build
ENV WORKDIR=/build \
    DATADIR=/data \
    VALHALLA_CONFIG=/build/valhalla.json
RUN mkdir -p ${WORKDIR} ${DATADIR}
RUN valhalla_build_config > ${VALHALLA_CONFIG}
COPY alias_tz.csv ${WORKDIR}

# Reads VALHALLA_CONFIG/VALHALLA_CONCURRENCY and execs valhalla_service as PID 1.
COPY valhalla-entrypoint.sh /usr/local/bin/valhalla-entrypoint.sh

# The entrypoint applies VALHALLA_CONFIG/VALHALLA_CONCURRENCY to this default
# command, and runs any other command as given.
ENTRYPOINT ["/usr/local/bin/valhalla-entrypoint.sh"]
CMD ["valhalla_service"]