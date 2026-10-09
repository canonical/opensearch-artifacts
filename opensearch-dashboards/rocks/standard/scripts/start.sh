#!/usr/bin/env bash

set -e
source "/usr/bin/set-conf.sh"

opensearch_dashboards_vars=(
    opensearch.hosts
    opensearch.ssl.certificate
    opensearch.ssl.certificateAuthorities
    opensearch.ssl.key
    opensearch.ssl.keyPassphrase
    opensearch.ssl.keystore.path
    opensearch.ssl.keystore.password
    opensearch.ssl.truststore.path
    opensearch.ssl.truststore.password
    opensearch.ssl.verificationMode
    opensearch_security.enabled
    server.host
    server.port
    server.ssl.certificate
    server.ssl.enabled
    server.ssl.key

)

OPENSEARCH_DASHBOARDS_CONF="${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml"

function set_base_config_props () {
    set_yaml_prop "${OPENSEARCH_DASHBOARDS_CONF}" "server.host" "0.0.0.0"
    set_yaml_prop "${OPENSEARCH_DASHBOARDS_CONF}" "opensearch_security.enabled" "false"
    set_yaml_prop "${OPENSEARCH_DASHBOARDS_CONF}" "path.data" "${OPENSEARCH_DASHBOARDS_VARLIB}"
}

function read_env_vars () {
    # transforms config variables to possible env vars. eg opensearch.hosts -> OPENSEARCH_HOSTS
    # see https://github.com/opensearch-project/OpenSearch-Dashboards/blob/72fa1239edc09780bdb854bef3c9ac70537ffd39/src/dev/build/tasks/os_packages/docker_generator/resources/bin/opensearch-dashboards-docker#L170
    for opensearch_dashboards_var in ${opensearch_dashboards_vars[*]}; do
        env_var=$(echo ${opensearch_dashboards_var^^} | tr . _)
        if [[ -v $env_var ]]; then
            value=${!env_var}
            set_yaml_prop "${OPENSEARCH_DASHBOARDS_CONF}" "${opensearch_dashboards_var}" "${value}"
        fi
    done
}

function start_opensearch_dashboards () {
    # start
    exec "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards \
        -c "${OPENSEARCH_DASHBOARDS_PATH_CONF}"/opensearch_dashboards.yml \
        -l "${OPENSEARCH_DASHBOARDS_VARLOG}"/opensearch_dashboards.log
}

set_base_config_props
read_env_vars
start_opensearch_dashboards
