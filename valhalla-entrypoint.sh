#!/bin/sh
# Entrypoint for the Valhalla service image.
#
# Follows the docker-library convention: only apply Valhalla's defaults when
# starting the service, and otherwise run whatever command was given, so that
# `docker run <image> bash` and `docker run <image> valhalla_build_tiles ...`
# behave as expected. See "consistency" in
# https://github.com/docker-library/official-images
#
# 'exec' replaces this shell, so the process we start becomes PID 1 and
# receives signals directly (needed for clean container shutdown).

set -e

# A bare flag is a flag for the service, not a command of its own, so that
# e.g. `docker run <image> --version` reaches valhalla_service.
case "$1" in
    '' | -*) set -- valhalla_service "$@" ;;
esac

# Anything other than a plain `valhalla_service` runs exactly as given.
if [ "$1" != valhalla_service ] || [ "$#" -ne 1 ]; then
    exec "$@"
fi

VALHALLA_CONFIG="${VALHALLA_CONFIG:-/build/valhalla.json}"
VALHALLA_CONCURRENCY="${VALHALLA_CONCURRENCY:-1}"

# Without tiles, valhalla_service still starts and answers every request with an
# error, so the container looks healthy while serving nothing. Fail fast with an
# explanation instead. Set VALHALLA_SKIP_TILE_CHECK=1 to bypass this, e.g. when
# tiles are mounted after startup.
# The config is parsed only if it is readable and valid JSON. Checking that up
# front keeps `set -e` from aborting the script on a jq failure (an assignment
# from a command substitution does propagate its exit status), which would kill
# the container with a bare parse error instead of letting valhalla_service
# report the config problem itself.
if [ -z "${VALHALLA_SKIP_TILE_CHECK}" ] && [ -r "${VALHALLA_CONFIG}" ] &&
   jq . "${VALHALLA_CONFIG}" >/dev/null 2>&1; then
    tile_extract=$(jq -r '.mjolnir.tile_extract // empty' "${VALHALLA_CONFIG}")
    tile_dir=$(jq -r '.mjolnir.tile_dir // empty' "${VALHALLA_CONFIG}")

    has_tiles=""
    if [ -n "${tile_extract}" ] && [ -f "${tile_extract}" ]; then
        has_tiles=1
    elif [ -n "${tile_dir}" ] && [ -d "${tile_dir}" ]; then
        # find's exit status is deliberately discarded: a partial walk (an
        # unreadable subdirectory, a transient error) should still be treated as
        # "no tiles found" and reach the message below, never abort the script.
        found=$(find "${tile_dir}" -name '*.gph' -print -quit 2>/dev/null || true)
        if [ -n "${found}" ]; then
            has_tiles=1
        fi
    fi

    if [ -z "${has_tiles}" ]; then
        cat >&2 <<EOF
[ERROR] No Valhalla tiles found - refusing to start.

Without tiles valhalla_service starts normally but fails every request, so the
container looks healthy while serving nothing. Checked, per ${VALHALLA_CONFIG}:

  tile_extract: ${tile_extract:-<unset>} (no such file)
  tile_dir:     ${tile_dir:-<unset>} (no .gph tiles)

Mount an unpacked tile directory:

  docker run -v /path/to/tiles:${tile_dir:-/data/valhalla}:ro -p 8002:8002 <image>

or, if you have one, a tile extract built by valhalla_build_extract:

  docker run -v /path/to/tiles.tar:${tile_extract:-/data/valhalla/tiles.tar}:ro -p 8002:8002 <image>

Interline Valhalla Tilepacks (https://www.interline.io/valhalla/tilepacks/,
fetched with planetutils' valhalla_tilepack_download) ship as a gzipped tile
directory rather than a tile extract, so unpack one and mount the directory.

Set VALHALLA_SKIP_TILE_CHECK=1 to start anyway.
EOF
        exit 1
    fi
fi

exec valhalla_service "${VALHALLA_CONFIG}" "${VALHALLA_CONCURRENCY}"
