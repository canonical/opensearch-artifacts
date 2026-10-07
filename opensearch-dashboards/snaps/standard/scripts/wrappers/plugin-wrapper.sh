#!/usr/bin/env bash

set -eu


# Bundled plugins belong to the snap: reject their removal before the native
# tool runs, which would unlink them from this revision.
function check_bundled_removal () {
    local argument command="" plugin="" value_follows="no"

    for argument in "$@"; do
        if [ "${value_follows}" = "yes" ]; then
            value_follows="no"
            continue
        fi
        case "${argument}" in
            -c|--config) value_follows="yes" ;;
            -*) ;;
            *)
                if [ -z "${command}" ]; then
                    command="${argument}"
                elif [ -z "${plugin}" ]; then
                    plugin="${argument}"
                fi
                ;;
        esac
    done

    if [ "${command}" = "remove" ] && [ -n "${plugin}" ] \
            && [ -d "${SNAP}/usr/share/opensearch-dashboards/shipped-plugins/$(basename -- "${plugin}")" ]; then
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
