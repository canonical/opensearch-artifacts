#!/bin/bash

set -e

# Match the native plugin-tool apps exposed by the standard 3.x snap while
# retaining the writable plugin paths used by existing 2.x installations.
exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid snap_daemon -- \
    bash "${OPENSEARCH_PLUGINS}/${plugin_tool}" "${@}"
