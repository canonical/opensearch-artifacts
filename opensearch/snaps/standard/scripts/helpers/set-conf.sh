#!/usr/bin/env bash


function replace_in_file() {
    "${SNAP}"/usr/bin/setpriv \
        --reuid snap_daemon -- sed -i "s@${2}@${3}@" "${1}"
}


# Sets a setting to a string, e.g. set_yaml_prop f cluster.name "a,b"
function set_yaml_prop() {
    "${SNAP}"/usr/bin/yq -y -i --arg k "${2}" --arg v "${3}" '.[$k] = $v' "${1}"
}

# Sets a setting to a JSON value, e.g. set_yaml_prop_json f node.roles '[]'
function set_yaml_prop_json() {
    "${SNAP}"/usr/bin/yq -y -i --arg k "${2}" --argjson v "${3}" '.[$k] = $v' "${1}"
}

# Sets a setting to the list of the given items, one per argument,
# e.g. set_yaml_list f network.host _local_ _site_
function set_yaml_list() {
    local target_file="${1}" key="${2}" item
    shift 2
    set_yaml_prop_json "${target_file}" "${key}" '[]'
    for item in "$@"; do
        add_yaml_list_item "${target_file}" "${key}" "${item}"
    done
}

# Adds an item to a list setting unless already present, keeping the others
function add_yaml_list_item() {
    "${SNAP}"/usr/bin/yq -y -i --arg k "${2}" --arg v "${3}" \
        '.[$k] |= ((. // []) | (if type == "array" then . else [.] end)
                   | if any(.[]; . == $v) then . else . + [$v] end)' "${1}"
}

function remove_yaml_prop() {
    "${SNAP}"/usr/bin/yq -y -i --arg k "${2}" 'del(.[$k])' "${1}"
}
