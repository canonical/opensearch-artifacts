#!/usr/bin/env bash

set -e -o pipefail

# Keep the historical filesystem entry point, with the same account and group
# as the supported app (custom plugins can install configuration and bin files).
exec snap run opensearch.plugin "${@}"
