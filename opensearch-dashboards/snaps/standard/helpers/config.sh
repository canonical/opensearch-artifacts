#!/usr/bin/env bash

# Shared helpers for seeding and editing the OpenSearch Dashboards
# configuration, which lives in $SNAP_COMMON so it survives refreshes.

OSD_CONF_FILE="${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml"
OSD_CA_FILE="${OPENSEARCH_DASHBOARDS_PATH_CERTS}/opensearch-ca.pem"
OSD_DEFAULT_HOSTS='["https://localhost:9200"]'


# Set a top-level (flat, dotted) key of the config file to a JSON value.
function set_conf_json () {
    local file="${1}"
    local key="${2}"
    local json_value="${3}"

    yq -y -i --arg k "${key}" --argjson v "${json_value}" \
        '.[$k] = $v' "${file}"
}


function copy_missing_files () {
    local src

    for src in "${1}"/*; do
        [ -e "${2}/$(basename "${src}")" ] || cp -r "${src}" "${2}/"
    done
}


# Seed the configuration in $SNAP_COMMON when missing, migrating it from
# $SNAP_DATA (prior revisions) or copying the upstream one pointed at the local
# OpenSearch over https. An existing configuration is never modified.
#
# Permissions are set before handing the files to snap_daemon: root can not
# chmod files it does not own under strict confinement.
function seed_config () {
    local legacy_conf_dir="${SNAP_DATA}/etc/opensearch-dashboards"

    [ ! -f "${OSD_CONF_FILE}" ] || return 0

    mkdir -p "${OPENSEARCH_DASHBOARDS_PATH_CONF}" \
        "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"

    if [ -f "${legacy_conf_dir}/opensearch_dashboards.yml" ]; then
        copy_missing_files "${legacy_conf_dir}" \
            "${OPENSEARCH_DASHBOARDS_PATH_CONF}"
    else
        copy_missing_files "${SNAP}/etc/opensearch-dashboards" \
            "${OPENSEARCH_DASHBOARDS_PATH_CONF}"
        set_conf_json "${OSD_CONF_FILE}" "opensearch.hosts" \
            "${OSD_DEFAULT_HOSTS}"
    fi

    set_conf_json "${OSD_CONF_FILE}" "path.data" \
        "$(jq -n --arg v "${OPENSEARCH_DASHBOARDS_VARLIB}" '$v')"

    chmod 770 "${OPENSEARCH_DASHBOARDS_PATH_CONF}" \
        "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"
    find "${OPENSEARCH_DASHBOARDS_PATH_CONF}" -type f -exec chmod 660 {} \;
    set_access_restrictions "${OPENSEARCH_DASHBOARDS_PATH_CONF}"
}
