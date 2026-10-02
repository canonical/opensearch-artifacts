#!/usr/bin/env bash

set -e -o pipefail

# Only called from within the snap environment
exec /snap/opensearch/current/usr/share/opensearch/shipped-bin/opensearch-plugin.orig "${@}"
