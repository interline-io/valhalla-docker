# Valhalla Dockerfiles

Dockerfiles to compile Valhalla from source. The main Dockerfile is a two-stage build, with the first stage creating installing all the compiler, library, and dev toolchains necessary to compile Valhalla and friends, with the second stage copying out these binary products from `/usr/local/` and creating a smaller image with only Valhalla run-time dependencies that can then be used as a base image for further customization.

