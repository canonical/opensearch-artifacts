#!/usr/bin/env bash

set -eu


# Bundled plugins belong to the snap: reject their removal before the native
# tool runs, which would unlink them from this revision. The native tool
# resolves the name in the plugins directory: only accept a directory name.
function check_bundled_removal () {
    local argument command="" plugin="" plugin_given="no" value_follows="no" options="yes"

    # As the native tool (commander) parses them.
    for argument in "$@"; do
        if [ "${value_follows}" = "yes" ]; then
            value_follows="no"
            continue
        fi
        case "${options}:${argument}" in
            yes:--) options="no" ;;
            yes:--config|yes:-c) value_follows="yes" ;;
            # -c<file>, or short options combined, e.g. -qc <file>.
            yes:-c?*) ;;
            yes:-*c) value_follows="yes" ;;
            yes:-*) ;;
            *)
                if [ -z "${command}" ]; then
                    command="${argument}"
                elif [ "${plugin_given}" = "no" ]; then
                    plugin="${argument}"
                    plugin_given="yes"
                fi
                ;;
        esac
    done

    [ "${command}" = "remove" ] && [ "${plugin_given}" = "yes" ] || return 0

    case "${plugin}" in
        ""|.|..|*/*)
            echo "'${plugin}' is not the name of a plugin directory. No changes were made." >&2
            exit 64
            ;;
    esac
    if [ -d "${SNAP}/usr/share/opensearch-dashboards/shipped-plugins/${plugin}" ]; then
        echo "Plugin '${plugin}' is bundled with this snap and cannot be removed. No changes were made." >&2
        exit 64
    fi
}


check_bundled_removal "$@"

exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-plugin "$@"
