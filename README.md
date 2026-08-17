# Interline's Valhalla Dockerfile

A Dockerfile to compile the [Valhalla](https://github.com/valhalla/valhalla) routing engine from source.

The main Dockerfile is a two-stage build, with the first stage installing all the compiler, library, and dev toolchains necessary to compile Valhalla and friends, with the second stage copying out these binary products from `/usr/local/` and creating a smaller image with only Valhalla run-time dependencies that can then be used as a base image for further customization.

Bring your own tiles. Or use PlanetUtils and its [`valhalla_tilepack_download`](https://github.com/interline-io/planetutils#valhalla_tilepack_download) command to download [Valhalla Tilepacks](https://www.interline.io/valhalla/tilepacks/) to use within this container.

## Usage

The default entrypoint runs `valhalla_service`, which listens on port **8002**. Tiles are not included in the image. The bundled config reads them from either an unpacked tile directory at `/data/valhalla`, or a `valhalla_build_extract` tile extract at `/data/valhalla/tiles.tar`:

```
docker run -p 8002:8002 -v /path/to/tiles:/data/valhalla:ro ghcr.io/interline-io/valhalla-docker/valhalla:latest
```

Note that [Valhalla Tilepacks](https://www.interline.io/valhalla/tilepacks/) ship as a gzipped tile *directory*, not a tile extract, so unpack one and mount the directory as above — mounting the tarball itself at `/data/valhalla/tiles.tar` will not work.

Then query it:

```
curl 'http://localhost:8002/status'
```

If no tiles are found the container exits with an explanation rather than starting. Valhalla would otherwise come up normally and fail every request, which looks like a healthy container.

Any other command runs as given, so the image doubles as a toolbox for the rest of the Valhalla binaries. The tile check only applies to the default service command:

```
docker run --rm -v /path/to/data:/data <image> valhalla_build_tiles -c /build/valhalla.json extract.osm.pbf
docker run --rm -it <image> bash
```

### Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `VALHALLA_CONFIG` | `/build/valhalla.json` | Config file the service reads. A default is generated at build time by `valhalla_build_config`. |
| `VALHALLA_CONCURRENCY` | `1` | Worker threads passed to `valhalla_service`. |
| `VALHALLA_SKIP_TILE_CHECK` | unset | Set to `1` to start even when no tiles are present, e.g. when tiles are mounted after startup. |

The image also sets `WORKDIR=/build` and `DATADIR=/data`.

### Building locally

```
docker build -t valhalla .
```

The Valhalla compile defaults to `-j$(nproc)`. Each heavy C++ translation unit can use 1-2 GB, so on a memory-constrained machine (including Docker Desktop with a small VM) limit the parallelism or the build will be OOM-killed:

```
docker build --build-arg MAKE_JOBS=2 -t valhalla .
```

The Valhalla and [prime_server](https://github.com/kevinkreiser/prime_server) versions are pinned as `ARG`s at the top of the Dockerfile. Valhalla uses prime_server for the HTTP service layer, and it is compiled from source in the same stage.

## Download from GitHub Packages

Images are built by GitHub Actions and published to GitHub at [`ghcr.io/interline-io/valhalla-docker/valhalla`](https://github.com/interline-io/valhalla-docker/pkgs/container/valhalla-docker%2Fvalhalla)

_Note_: Previously we published images to Docker Hub at [`interline/valhalla`](https://hub.docker.com/r/interline/valhalla). Older tags are still available to download. Unfortunately, [Docker Hub is no longer able to provide a free tier to open-source projects](https://www.docker.com/blog/changes-to-docker-hub-autobuilds/).
