#!/usr/bin/env bash

# The configuration is kept in ${SNAP_COMMON}/etc/opensearch, shared by the
# revisions. The previous revisions kept it in the revision specific
# ${SNAP_DATA}/etc/opensearch, which snapd copies on refresh and keeps for
# revert. A marker in ${SNAP_DATA} tells that the configuration in use is the
# one in ${SNAP_COMMON}: snapd copies it along with ${SNAP_DATA} on refresh,
# and it is missing when refreshing from a revision that did not use it.

CONFIG_IN_COMMON_MARKER="${SNAP_DATA}/.config-in-snap-common"

# Matches the configuration paths of the previous revisions, through the
# "current" link or a revision number
LEGACY_CONF_PATH_REGEX="/var/snap/${SNAP_INSTANCE_NAME:-opensearch}/(current|x?[0-9]+)/etc/opensearch"

# Set to "yes" by migrate_config_to_common when it migrated the configuration
CONFIG_MIGRATED="no"


function mark_config_in_common () {
    touch "${CONFIG_IN_COMMON_MARKER}"
}


# Copies a directory as root, keeping the modes, owners and timestamps. The
# hooks are not granted CAP_FOWNER and CAP_DAC_OVERRIDE: the files are given
# their modes while root still owns them, then their owners, and the files
# root cannot read (e.g. the keystore, snap_daemon:snap_daemon) are copied as
# their owner once the directories have their owners.
function copy_dir_preserving () {
    local src="${1}" dst="${2}" rel owner
    local -a not_readable=()
    local -A paths_by_owner=()

    # thousands of files: keep them out of the xtrace output
    { local xtrace="${-//[^x]/}"; set +x; } 2>/dev/null

    # Fails on the files root cannot read, copied below
    cp -r --preserve=mode,timestamps "${src}" "${dst}" 2>/dev/null || true
    while IFS= read -r -d '' rel; do
        if [ ! -e "${dst}/${rel}" ] && [ ! -L "${dst}/${rel}" ]; then
            not_readable+=("${rel}")
        fi
    done < <(cd "${src}" && find . -mindepth 1 -print0)

    # Point the settings at the new location while root owns the files, e.g.
    # the certificates in opensearch.yml and the trust store in jvm.options
    rewrite_config_paths "${dst}"

    while IFS= read -r -d '' owner && IFS= read -r -d '' rel; do
        [ -e "${dst}/${rel}" ] || [ -L "${dst}/${rel}" ] || continue
        paths_by_owner["${owner}"]+="${dst}/${rel}"$'\n'
    done < <(cd "${src}" && find . -printf '%u:%g\0%p\0')
    for owner in "${!paths_by_owner[@]}"; do
        printf '%s' "${paths_by_owner["${owner}"]}" \
            | tr '\n' '\0' | xargs -0 chown --no-dereference "${owner}"
    done

    for rel in "${not_readable[@]}"; do
        echo "Copying ${rel} as its owner."
        "${SNAP}"/usr/bin/setpriv \
            --clear-groups \
            --reuid "$(stat -c %u "${src}/${rel}")" \
            --regid "$(stat -c %g "${src}/${rel}")" -- \
            cp -r --preserve=mode,timestamps "${src}/${rel}" "${dst}/${rel}"
    done

    [ -z "${xtrace}" ] || set -x
}


function rewrite_config_paths () {
    local file
    while IFS= read -r -d '' file; do
        echo "Updating the configuration paths in ${file}."
        sed -i -E "s@${LEGACY_CONF_PATH_REGEX}@${OPENSEARCH_PATH_CONF}@g" "${file}"
    done < <(grep -rlIZE "${LEGACY_CONF_PATH_REGEX}" "${1}" 2>/dev/null || true)
}


# Moves the configuration of a previous revision into ${SNAP_COMMON}: run
# from the post-refresh hook, as root.
function migrate_config_to_common () {
    local legacy_conf="${SNAP_DATA}/etc/opensearch"
    local staging="${OPENSEARCH_PATH_CONF}.migrating"
    local backup

    if [ -f "${CONFIG_IN_COMMON_MARKER}" ]; then
        echo "The configuration is already in ${OPENSEARCH_PATH_CONF}."
        return 0
    fi

    if [ ! -d "${legacy_conf}" ]; then
        echo "No configuration to migrate in ${legacy_conf}."
        mark_config_in_common
        return 0
    fi

    echo "Migrating the configuration from ${legacy_conf} to ${OPENSEARCH_PATH_CONF}."
    mkdir -p "$(dirname "${OPENSEARCH_PATH_CONF}")"
    # Left by an interrupted migration
    rm -rf "${staging}"
    # The original is left in place for the previous revisions, which read
    # it from there.
    copy_dir_preserving "${legacy_conf}" "${staging}"

    # Left by a revision using ${SNAP_COMMON} before a revert to a revision
    # that did not: the configuration of the latter is the one in use.
    if [ -e "${OPENSEARCH_PATH_CONF}" ]; then
        backup="${OPENSEARCH_PATH_CONF}.$(date +%Y%m%d%H%M%S).bak"
        echo "Moving the configuration in ${OPENSEARCH_PATH_CONF} to ${backup}."
        mv "${OPENSEARCH_PATH_CONF}" "${backup}"
    fi
    mv "${staging}" "${OPENSEARCH_PATH_CONF}"

    mark_config_in_common
    CONFIG_MIGRATED="yes"
}


# Whether the migrated configuration was set up, e.g. with opensearch.setup
function config_is_set_up () {
    "${SNAP}"/usr/bin/yq -e '."node.name" // empty' \
        "${OPENSEARCH_PATH_CONF}/opensearch.yml" >/dev/null 2>&1
}
