#!/bin/bash

set -e

# Generic wrapper for the tools shipped by OpenSearch plugins, exposed as
# snap apps. The tool is selected via the 'plugin_tool' app environment
# variable, relative to the writable plugins home (OPENSEARCH_PLUGINS).
# Runs as snap_daemon so it can read the keystore, certificates and other
# snap_daemon-owned state.
"${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid snap_daemon -- \
    bash "${OPENSEARCH_PLUGINS}/${plugin_tool}" "${@}"
