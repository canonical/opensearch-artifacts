#!/usr/bin/env bash

set -eu

# Save only plugin-owned directories, using the same account as the plugin
# installer. Live configuration remains shared; recovery copies stay in SNAP_DATA.
exec "${SNAP}/usr/bin/setpriv" \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    "${SNAP}/usr/bin/python3" "${SNAP}/opt/opensearch/helpers/plugin-configuration.py" save
