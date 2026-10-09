#!/usr/bin/env bash


function replace_in_file() {
    "${SNAP}"/usr/bin/setpriv \
        --reuid snap_daemon -- sed -i "s@${2}@${3}@" "${1}"
}


# OpenSearch joins nested mapping keys with dots, including keys already containing dots.
# Edit every spelling of one setting, preserving siblings. The last spelling is effective.
function edit_yaml_setting() {
    local target_file="${1}" key="${2}" operation="${3}"
    shift 3
    "${SNAP}"/usr/bin/yq -y -i --arg k "${key}" "$@" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | (if $paths | length > 0 then getpath($paths[-1]) else null end) as $old
        | delpaths($paths)
        | '"${operation}" "${target_file}"
}


# Read the last spelling of a setting, whether its keys are dotted, nested, or mixed.
function get_yaml_prop() {
    "${SNAP}"/usr/bin/yq -r --arg k "${2}" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | if $paths | length > 0 then getpath($paths[-1]) else empty end
    ' "${1}"
}


# Sets a setting to a string, e.g. set_yaml_prop f cluster.name "a,b"
function set_yaml_prop() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --arg v "${3}"
}

# Sets a setting to a JSON value, e.g. set_yaml_prop_json f node.roles '[]'
function set_yaml_prop_json() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --argjson v "${3}"
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
    edit_yaml_setting "${1}" "${2}" \
        '.[$k] = (($old // []) | (if type == "array" then . else [.] end)
                   | if any(.[]; . == $v) then . else . + [$v] end)' --arg v "${3}"
}

function remove_yaml_prop() {
    edit_yaml_setting "${1}" "${2}" '.'
}
