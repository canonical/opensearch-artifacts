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

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root: sudo ${SNAP_INSTANCE_NAME}.plugin $*" >&2
    exit 1
fi

# The plugins and the configuration belong to snap_daemon, with the root group.
exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-plugin "$@"
