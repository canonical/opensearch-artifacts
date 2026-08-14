#!/usr/bin/env bash

set -e -o pipefail

snap run --shell opensearch-charmed.daemon -- /snap/opensearch-charmed/current/usr/share/opensearch/bin/opensearch-plugin.orig "${@}"
