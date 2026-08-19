#!/usr/bin/env bash

set -eu

source "/usr/bin/get-conf.sh"

function fetch_exporter_args () {
    DASHBOARDS_HOST="localhost"
    DASHBOARDS_PORT=$( get_yaml_prop "${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml" "server.port" "5601" )
    DASHBOARDS_USER=$( get_yaml_prop "${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml" "opensearch.username" "" )
    DASHBOARDS_PASSWORD=$( get_yaml_prop "${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml" "opensearch.password" "" )
    DASHBOARDS_SERVER_PATH=$( get_yaml_prop "${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml" "server.basePath" "" )
    ssl_enabled=$(get_yaml_prop "${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml" "server.ssl.enabled" "false")
    if [[ "${ssl_enabled}" == "true" ]]; then
        SCHEME="https"
    else
        SCHEME="http"
    fi
}

function start_exporter () {
    OPENSEARCH_DASHBOARDS_USER="${DASHBOARDS_USER}" \
    OPENSEARCH_DASHBOARDS_PASSWORD="${DASHBOARDS_PASSWORD}" \
    exec /usr/bin/prometheus-opensearch-dashboards-exporter \
        --url ${SCHEME}://${DASHBOARDS_HOST}:${DASHBOARDS_PORT}${DASHBOARDS_SERVER_PATH}
}


fetch_exporter_args
start_exporter
