#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/snap-logger.sh "cleanup"
source "${OPS_ROOT}"/helpers/set-conf.sh


opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
cleanup_root_certs() {
    local certs_dir="${OPENSEARCH_PATH_CERTS}"
    # Remove only root certificates and keys, leaving other certs intact.
    rm -f "${certs_dir}"/root-ca*.pem "${certs_dir}"/root-ca.srl
    # Remove yaml properties related to root certs from opensearch.yml
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemtrustedcas_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemtrustedcas_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.enforce_hostname_verification"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.enabled"
}

cleanup_admin_certs() {
    local certs_dir="${OPENSEARCH_PATH_CERTS}"
    # Remove only admin certificates and keys, leaving other certs intact.
    rm -f "${certs_dir}"/admin*.pem
    # Remove yaml properties related to admin certs from opensearch.yml
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.authcz.admin_dn"
}

cleanup_node_certs() {
    local certs_dir="${OPENSEARCH_PATH_CERTS}"
    # Remove only node certificates and keys, leaving other certs intact.
    rm -f "${certs_dir}"/node-*.*
    # Remove yaml properties related to node certs from opensearch.yml
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemcert_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemkey_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemkey_password"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemcert_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_filepath"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_password"
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.nodes_dn"
}