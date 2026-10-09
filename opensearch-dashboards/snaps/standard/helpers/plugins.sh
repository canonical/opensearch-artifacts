#!/usr/bin/env bash

# The plugins of a revision live in its writable data: links to the plugins
# bundled with the snap, plus the custom ones installed with the plugin app.
# A refresh copies them to the new revision, a revert uses the old ones again.

OSD_PLUGINS="${SNAP_DATA}/usr/share/opensearch-dashboards/plugins"
OSD_SHIPPED_PLUGINS="${SNAP}/usr/share/opensearch-dashboards/shipped-plugins"
OSD_SHIPPED_LINK_DIR="${SNAP_CURRENT}/usr/share/opensearch-dashboards/shipped-plugins"
# The custom plugins removed by the refresh to this revision, which the daemon
# reports each time it starts: snapd discards the output of a successful hook.
OSD_REMOVED_PLUGINS="${SNAP_DATA}/removed-plugins.log"


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


# Why OpenSearch Dashboards can not load a custom plugin, or nothing. As
# upstream, a plugin built for another version is loaded, with a warning. The
# manifest is read as snap_daemon, which owns the plugins.
function incompatibility () {
    as_snap_daemon jq -e '.id | strings' "${1}/opensearch_dashboards.json" > /dev/null 2>&1 \
        || echo "missing or invalid opensearch_dashboards.json"
}


# Remove a plugin as snap_daemon, which owns the plugins: root can not delete
# the files of another user under strict confinement. A plugin copied by root
# is first handed over to snap_daemon; root can not enter the directories of
# snap_daemon without permissions for the group, which snap_daemon can delete.
function remove_plugin () {
    [ -L "${1}" ] || chown -R snap_daemon "${1}" 2> /dev/null || true
    as_snap_daemon rm -rf -- "${1}"
}


# Keep the custom plugins this revision can load and link its bundled
# plugins. Only this revision's data is changed: a revert gets back the
# previous revision's plugins.
function ensure_plugins_dir () {
    local path name id reason
    local -A bundled_ids=() reasons=()

    # Left by the refresh to the previous revision.
    rm -f "${OSD_REMOVED_PLUGINS}"

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
        id="$(as_snap_daemon jq -r '.id // empty' "${path}/opensearch_dashboards.json" 2> /dev/null || true)"
        if [ -z "${reason}" ] && [ -n "${id}" ] && [ -n "${bundled_ids[${id}]+x}" ]; then
            reason="its id ${id} is the one of a plugin bundled with this snap"
        fi

        [ -z "${reason}" ] || reasons["${name}"]="${reason}"
    done

    for name in "${!reasons[@]}"; do
        remove_plugin "${OSD_PLUGINS:?}/${name}"
        echo "Removed plugin ${name} from revision ${SNAP_REVISION}: ${reasons[${name}]}." \
            "The previous revision keeps it." | tee -a "${OSD_REMOVED_PLUGINS}"
    done

    link_shipped_plugins
}
