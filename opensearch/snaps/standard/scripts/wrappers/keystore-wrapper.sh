#!/usr/bin/env bash

set -e -o pipefail

# Called by bin/opensearch on start, already in the snap environment
exec /snap/opensearch/current/usr/share/opensearch/shipped-bin/opensearch-keystore.orig "${@}"
