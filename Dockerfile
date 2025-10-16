# Dockerfile to build Valhalla in stage 1, 
#   then build our image by pulling out 
#   the compiled Valhalla binaries from stage 1.

# #####################################
# ############ STAGE 1 ################
# #####################################

ARG VALHALLA_VERSION=3.6.0-rc1
ARG VALHALLA_COMMIT=d391387b40c63ed64bab927db8f17a1498805ffe
ARG PRIME_SERVER_COMMIT=4508553b2dd29fadfafcc7c766aa6e9b94455fcb
FROM ubuntu:24.04
ARG VALHALLA_VERSION
ARG VALHALLA_COMMIT
ARG PRIME_SERVER_COMMIT

# Install base packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
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
    libgeos++-dev \
    libgeos-dev \
    libidn11-dev \
    libluajit-5.1-dev \
    liblz4-dev \
    libspatialite-dev \
    libsqlite3-dev \
    libsqlite3-mod-spatialite \
    libprotobuf-dev \
    libtool \
    libzmq3-dev \
    make \
    osmctools \
    osmosis \
    parallel \
    pkgconf \
    protobuf-compiler \
    python3-all-dev \
    python3-pip \
    software-properties-common \
    spatialite-bin \
    vim-common \
    wget \
    zlib1g-dev

# install a more recent cmake than available through apt-get for Ubuntu 18.04
RUN curl -sSL https://github.com/Kitware/CMake/releases/download/v3.21.1/cmake-3.21.1-linux-x86_64.tar.gz | tar -xzC /opt
ENV PATH="/opt/cmake-3.21.1-linux-x86_64/bin/:${PATH}"

RUN mkdir -p /src && cd /src

# prime_server
RUN git clone https://github.com/kevinkreiser/prime_server.git && (cd prime_server && git checkout ${PRIME_SERVER_COMMIT} && git submodule update --init --recursive && mkdir -p build && cd build && cmake .. && make -j2 install)

# valhalla
# NOTE: -DENABLE_BENCHMARKS=OFF is because of https://github.com/valhalla/valhalla/issues/3200
# NOTE: -ENABLE_SINGLE_FILES_WERROR=OFF because of https://github.com/valhalla/valhalla/issues/3157
RUN git clone https://github.com/valhalla/valhalla.git && (cd valhalla && git checkout ${VALHALLA_COMMIT} -b build && git submodule update --init --recursive && mkdir -p build && cd build && cmake .. -DCMAKE_C_COMPILER=gcc -DPKG_CONFIG_PATH=/usr/local/lib/pkgconfig -DCMAKE_BUILD_TYPE=Release -DENABLE_NODE_BINDINGS=OFF -DENABLE_PYTHON_BINDINGS=OFF -DENABLE_BENCHMARKS=OFF -DENABLE_SINGLE_FILES_WERROR=OFF && make -j2 install) && rm -rf /src

# #####################################
# ############ STAGE 2 ################
# #####################################

FROM ubuntu:24.04
ARG VALHALLA_VERSION
ARG VALHALLA_CONCURRENCY=1

# Copy ARG to ENV
ENV VALHALLA_VERSION=${VALHALLA_VERSION}
ENV VALHALLA_CONCURRENCY=${VALHALLA_CONCURRENCY}

# Utilities needed
RUN apt-get update && apt-get install --no-install-recommends -y apt-transport-https curl libcurl4 ca-certificates gnupg && rm -rf /var/lib/apt/lists/*

# Install apt packages packages
RUN apt-get update && apt-get install --no-install-recommends -y \
    libluajit-5.1-2 \
    libprotobuf-dev \
    libzmq5 \
    libczmq4 \
    libsqlite3-mod-spatialite \
    python3-pip \
    spatialite-bin \
    jo \
    jq \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy previous installs
COPY --from=0 /usr/local /usr/local

# Fix things
ENV LD_LIBRARY_PATH "${LD_LIBRARY_PATH}:/usr/local/lib"
RUN ln -s /usr/lib/x86_64-linux-gnu/mod_spatialite.so.7.1.0 /usr/lib/x86_64-linux-gnu/mod_spatialite

# Setup
WORKDIR /build
ENV WORKDIR=/build DATADIR=/data VALHALLA_CONFIG=/build/valhalla.json
RUN mkdir -p ${WORKDIR} ${DATADIR}
RUN valhalla_build_config > ${VALHALLA_CONFIG}
ADD alias_tz.csv ${WORKDIR}

# Default command
CMD valhalla_service ${VALHALLA_CONFIG} ${VALHALLA_CONCURRENCY}