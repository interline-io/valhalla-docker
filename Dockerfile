# Dockerfile to build Valhalla in stage 1, 
#   then build our image by pulling out 
#   the compiled Valhalla binaries from stage 1.

# #####################################
# ############ STAGE 1 ################
# #####################################

ARG VALHALLA_VERSION=3.8.3
ARG VALHALLA_COMMIT=a60c7cbfc83e073f50887cd27e0109d02e6b64e5
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

# Install base packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    cmake \
    curl \
    g++ \
    gcc \
    git \
    jq \
    lcov \
    libbz2-dev \
    libboost-all-dev \
    libcurl4-openssl-dev \
    libczmq-dev \
    libexpat1-dev \
    libgdal-dev \
    libgeos++-dev \
    libgeos-dev \
    libgeotiff-dev \
    libidn11-dev \
    libluajit-5.1-dev \
    liblz4-dev \
    libspatialite-dev \
    libsqlite3-dev \
    libsqlite3-mod-spatialite \
    libprotobuf-dev \
    libssl-dev \
    libtool \
    libzmq3-dev \
    make \
    osmctools \
    osmosis \
    parallel \
    pkgconf \
    protobuf-compiler \
    python3 \
    software-properties-common \
    spatialite-bin \
    vim-common \
    wget \
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
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    libcurl4 \
    libluajit-5.1-2 \
    libprotobuf-lite32t64 \
    libzmq5 \
    libczmq4 \
    libsqlite3-mod-spatialite \
    libgeotiff5 \
    libgdal34t64 \
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

# Create entrypoint script that uses env vars with exec for proper signal handling
# The 'exec' replaces the shell process, making valhalla_service PID 1 for proper signal handling
RUN echo '#!/bin/sh\nexec valhalla_service "${VALHALLA_CONFIG:-/build/valhalla.json}" "${VALHALLA_CONCURRENCY:-1}"' > /usr/local/bin/valhalla-entrypoint.sh && \
    chmod +x /usr/local/bin/valhalla-entrypoint.sh

# Default command - uses entrypoint which reads env vars
ENTRYPOINT ["/usr/local/bin/valhalla-entrypoint.sh"]