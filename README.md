# Interline's Valhalla Dockerfile

A Dockerfile to compile the [Valhalla](https://github.com/valhalla/valhalla) routing engine from source.

The main Dockerfile is a two-stage build, with the first stage creating installing all the compiler, library, and dev toolchains necessary to compile Valhalla and friends, with the second stage copying out these binary products from `/usr/local/` and creating a smaller image with only Valhalla run-time dependencies that can then be used as a base image for further customization.

Bring your own tiles. Or use PlanetUtils and its [`valhalla_tilepack_download`](https://github.com/interline-io/planetutils#valhalla_tilepack_download) command to download [Valhalla Tilepacks](https://www.interline.io/valhalla/tilepacks/) to use within this container.

## Download from Docker Hub

Images are built and published to Docker Hub at [`interline/valhalla`](https://hub.docker.com/r/interline/valhalla).