#!/usr/bin/env bash

# Shared helpers for seeding and editing the OpenSearch Dashboards
# configuration, which lives in $SNAP_COMMON so it survives refreshes.

OSD_CONF_FILE="${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml"
OSD_CA_FILE="${OPENSEARCH_DASHBOARDS_PATH_CERTS}/opensearch-ca.pem"

source "${OPS_ROOT}"/helpers/set-conf.sh


# The settings of the snap on top of the upstream configuration: the local
# OpenSearch over https, and the data in $SNAP_COMMON.
function set_default_settings () {
    set_yaml_prop_json "${1}" "opensearch.hosts" '["https://localhost:9200"]'
    set_yaml_prop "${1}" "path.data" "${OPENSEARCH_DASHBOARDS_VARLIB}"
}


# Seed the configuration in $SNAP_COMMON when missing, copying the upstream one
# pointed at the local OpenSearch over https. An existing configuration is
# never modified.
#
# Permissions are set before handing the files to snap_daemon: root can not
# chmod files it does not own under strict confinement.
function seed_config () {
    [ ! -f "${OSD_CONF_FILE}" ] || return 0

    mkdir -p "${OPENSEARCH_DASHBOARDS_PATH_CONF}" \
        "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"

    cp -r "${SNAP}"/etc/opensearch-dashboards/. "${OPENSEARCH_DASHBOARDS_PATH_CONF}/"
    set_default_settings "${OSD_CONF_FILE}"

    chmod 770 "${OPENSEARCH_DASHBOARDS_PATH_CONF}" \
        "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"
    find "${OPENSEARCH_DASHBOARDS_PATH_CONF}" -type f -exec chmod 660 {} \;
    set_access_restrictions "${OPENSEARCH_DASHBOARDS_PATH_CONF}"
}
