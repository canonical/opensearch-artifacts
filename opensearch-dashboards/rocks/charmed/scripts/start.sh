#!/usr/bin/env bash

set -e
source "/usr/bin/set-conf.sh"

function start_opensearch_dashboards () {
    # start
    exec "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards \
        -c "${OPENSEARCH_DASHBOARDS_PATH_CONF}"/opensearch_dashboards.yml \
        -l "${OPENSEARCH_DASHBOARDS_VARLOG}"/opensearch_dashboards.log
}

start_opensearch_dashboards