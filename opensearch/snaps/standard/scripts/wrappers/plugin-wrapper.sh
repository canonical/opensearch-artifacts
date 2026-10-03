#!/usr/bin/env bash

set -e -o pipefail

# Run the native tool and update this revision's saved configuration after removal.
# Other revisions keep their own copies for rollback.
exec "${SNAP}/usr/bin/python3" "${SNAP}/opt/opensearch/helpers/plugin-configuration.py" \
    run "${SNAP}/usr/share/opensearch/shipped-bin/opensearch-plugin.orig" "${@}"
