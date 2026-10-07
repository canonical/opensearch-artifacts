#!/usr/bin/env bash

# The plugins of a revision live in its writable data: links to the plugins
# bundled with the snap, plus the custom ones installed with the plugin app.
# A refresh copies them to the new revision, a revert uses the old ones again.

OSD_PLUGINS="${SNAP_DATA}/usr/share/opensearch-dashboards/plugins"
OSD_SHIPPED_PLUGINS="${SNAP}/usr/share/opensearch-dashboards/shipped-plugins"
OSD_SHIPPED_LINK_DIR="${SNAP_CURRENT}/usr/share/opensearch-dashboards/shipped-plugins"


function as_snap_daemon () {
    "${SNAP}"/usr/bin/setpriv \
        --clear-groups \
        --reuid snap_daemon \
        --regid root -- \
        "$@"
}


# Link every bundled plugin missing from the plugins directory.
function link_shipped_plugins () {
    local plugin name

    for plugin in "${OSD_SHIPPED_PLUGINS}"/*/; do
        [ -d "${plugin}" ] || continue
        name="$(basename "${plugin}")"
        if [ ! -L "${OSD_PLUGINS}/${name}" ]; then
            ln -s "${OSD_SHIPPED_LINK_DIR}/${name}" "${OSD_PLUGINS}/${name}"
        fi
    done
}


# 3.8.0 from 3.8.0, 3.8 or v3.8.0-rc1, as semver.coerce, which upstream uses.
function coerce_version () {
    local version

    version="$(grep -oE '[0-9]+(\.[0-9]+){0,2}' <<< "${1}" | head -n 1)"
    [ -n "${version}" ] || return 0
    while [[ "${version}" != *.*.* ]]; do
        version="${version}.0"
    done
    echo "${version}"
}


# Why a custom plugin can not be loaded by this revision, or nothing.
function incompatibility () {
    local manifest="${1}/opensearch_dashboards.json"
    local wanted current

    jq -e '.id | strings' "${manifest}" > /dev/null 2>&1 \
        || { echo "missing or invalid opensearch_dashboards.json"; return; }

    wanted="$(jq -r '.opensearchDashboardsVersion // empty' "${manifest}")"
    # Upstream accepts this value with any version.
    [ "${wanted}" != "opensearchDashboards" ] || return 0

    current="$(jq -r .version "${SNAP}/usr/share/opensearch-dashboards/package.json")"
    if [ -z "$(coerce_version "${wanted}")" ] \
            || [ "$(coerce_version "${wanted}")" != "$(coerce_version "${current}")" ]; then
        echo "built for OpenSearch Dashboards ${wanted:-unknown}, this snap is ${current}"
    fi
}


# Keep the custom plugins this revision can load and link its bundled
# plugins. Only this revision's data is changed: a revert gets back the
# previous revision's plugins.
function ensure_plugins_dir () {
    local path name id reason required changed
    local -A bundled_ids=() custom_ids=() removed_ids=() reasons=()

    for path in "${OSD_SHIPPED_PLUGINS}"/*/; do
        id="$(jq -r '.id // empty' "${path}/opensearch_dashboards.json" 2> /dev/null || true)"
        [ -z "${id}" ] || bundled_ids["${id}"]=1
    done

    for path in "${OSD_PLUGINS}"/*; do
        [ -e "${path}" ] || [ -L "${path}" ] || continue
        name="$(basename "${path}")"

        # The link to a bundled plugin: kept.
        if [ -d "${OSD_SHIPPED_PLUGINS}/${name}" ] && [ -L "${path}" ] \
                && [ "$(readlink "${path}")" = "${OSD_SHIPPED_LINK_DIR}/${name}" ]; then
            continue
        fi

        # A directory or another link with the name of a bundled plugin, which
        # gets linked again below, or a link that is not an installed plugin.
        if [ -d "${OSD_SHIPPED_PLUGINS}/${name}" ]; then
            reasons["${name}"]="replaced by the plugin bundled with this snap"
            continue
        elif [ -L "${path}" ]; then
            reasons["${name}"]="a link, not a plugin installed with the plugin app"
            continue
        fi

        reason="$(incompatibility "${path}")"
        id="$(jq -r '.id // empty' "${path}/opensearch_dashboards.json" 2> /dev/null || true)"
        if [ -z "${reason}" ] && [ -n "${id}" ] && [ -n "${bundled_ids[${id}]+x}" ]; then
            reason="its id ${id} is the one of a plugin bundled with this snap"
        fi

        if [ -n "${reason}" ]; then
            reasons["${name}"]="${reason}"
            [ -z "${id}" ] || removed_ids["${id}"]=1
        else
            custom_ids["${name}"]="${id}"
        fi
    done

    # A custom plugin requiring a removed one can not start either.
    changed=1
    while [ "${changed}" -eq 1 ]; do
        changed=0
        for name in "${!custom_ids[@]}"; do
            while read -r required; do
                if [ -n "${required}" ] && [ -n "${removed_ids[${required}]+x}" ]; then
                    reasons["${name}"]="it requires the removed plugin ${required}"
                    [ -z "${custom_ids[${name}]}" ] || removed_ids["${custom_ids[${name}]}"]=1
                    unset "custom_ids[${name}]"
                    changed=1
                    break
                fi
            done < <(jq -r '.requiredPlugins // [] | .[]' \
                "${OSD_PLUGINS}/${name}/opensearch_dashboards.json")
        done
    done

    for name in "${!reasons[@]}"; do
        as_snap_daemon rm -rf -- "${OSD_PLUGINS:?}/${name}"
        echo "Removed plugin ${name} from revision ${SNAP_REVISION}: ${reasons[${name}]}." \
            "The previous revision keeps it."
    done

    link_shipped_plugins
}
