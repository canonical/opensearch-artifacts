#!/usr/bin/env bash

set -e -o pipefail

tool=/snap/opensearch/current/usr/share/opensearch/shipped-bin/opensearch-plugin.orig

# Already in the snap environment: a nested snap run is denied under strict
# confinement
if [ "${SNAP_NAME:-}" = "opensearch" ]; then
    exec "${tool}" "${@}"
fi

snap run --shell opensearch.daemon -- "${tool}" "${@}"
