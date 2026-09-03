#!/usr/bin/env bash

set -e -o pipefail

snap run --shell opensearch-chiseled.daemon -- /snap/opensearch-chiseled/current/usr/share/opensearch/bin/opensearch-keystore.orig "${@}"
