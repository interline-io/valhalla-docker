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
if [ -z "${VALHALLA_SKIP_TILE_CHECK}" ] && [ -r "${VALHALLA_CONFIG}" ]; then
    tile_extract=$(jq -r '.mjolnir.tile_extract // empty' "${VALHALLA_CONFIG}")
    tile_dir=$(jq -r '.mjolnir.tile_dir // empty' "${VALHALLA_CONFIG}")

    has_tiles=""
    [ -n "${tile_extract}" ] && [ -f "${tile_extract}" ] && has_tiles=1
    if [ -z "${has_tiles}" ] && [ -n "${tile_dir}" ] && [ -d "${tile_dir}" ]; then
        [ -n "$(find "${tile_dir}" -name '*.gph' -print -quit 2>/dev/null)" ] && has_tiles=1
    fi

    if [ -z "${has_tiles}" ]; then
        cat >&2 <<EOF
[ERROR] No Valhalla tiles found - refusing to start.

Without tiles valhalla_service starts normally but fails every request, so the
container looks healthy while serving nothing. Checked, per ${VALHALLA_CONFIG}:

  tile_extract: ${tile_extract:-<unset>}
  tile_dir:     ${tile_dir:-<unset>} (no .gph tiles)

Mount a tilepack over the tile extract path, for example:

  docker run -v /path/to/tiles.tar:${tile_extract:-/data/valhalla/tiles.tar}:ro -p 8002:8002 <image>

Tilepacks are available at https://www.interline.io/valhalla/tilepacks/ and can
be fetched with planetutils' valhalla_tilepack_download.

Set VALHALLA_SKIP_TILE_CHECK=1 to start anyway.
EOF
        exit 1
    fi
fi

exec valhalla_service "${VALHALLA_CONFIG}" "${VALHALLA_CONCURRENCY}"
