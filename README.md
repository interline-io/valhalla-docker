# Interline's Valhalla Dockerfile

A Dockerfile to compile the [Valhalla](https://github.com/valhalla/valhalla) routing engine from source.

The main Dockerfile is a two-stage build, with the first stage creating installing all the compiler, library, and dev toolchains necessary to compile Valhalla and friends, with the second stage copying out these binary products from `/usr/local/` and creating a smaller image with only Valhalla run-time dependencies that can then be used as a base image for further customization.

Bring your own tiles. Or use PlanetUtils and its [`valhalla_tilepack_download`](https://github.com/interline-io/planetutils#valhalla_tilepack_download) command to download [Valhalla Tilepacks](https://www.interline.io/valhalla/tilepacks/) to use within this container.

## Download from GitHub Packages

Images are built by GitHub Actions and published to GitHub at [`ghcr.io/interline-io/valhalla-docker/valhalla`](https://github.com/interline-io/valhalla-docker/pkgs/container/valhalla-docker%2Fvalhalla)

_Note_: Previously we published images to Docker Hub at [`interline/valhalla`](https://hub.docker.com/r/interline/valhalla). Older tags are still available to download. Unfortunately, [Docker Hub is no longer able to provide a free tier to open-source projects](https://www.docker.com/blog/changes-to-docker-hub-autobuilds/).
