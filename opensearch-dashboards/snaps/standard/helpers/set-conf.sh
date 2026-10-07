#!/usr/bin/env bash

# Same helpers as the OpenSearch snap (opensearch/snaps/standard/scripts/helpers/set-conf.sh).


# OpenSearch Dashboards joins nested mapping keys with dots, including keys already containing
# dots. Edit every spelling of one setting, preserving siblings. The last spelling is effective.
# Unlike OpenSearch, an emptied parent (e.g. "opensearch: {}") replaces the dotted settings
# under it, so parents left empty are removed.
function edit_yaml_setting() {
    local target_file="${1}" key="${2}" operation="${3}"
    shift 3
    "${SNAP}"/usr/bin/yq -y -i --arg k "${key}" "$@" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | (if $paths | length > 0 then getpath($paths[-1]) else null end) as $old
        | delpaths($paths)
        | reduce ($paths[] | . as $p | range(($p | length) - 1; 0; -1) | $p[:.]) as $parent
            (.; if getpath($parent) == {} then delpaths([$parent]) else . end)
        | '"${operation}" "${target_file}"
}


# Read the last spelling of a setting, whether its keys are dotted, nested, or mixed.
function get_yaml_prop() {
    "${SNAP}"/usr/bin/yq -r --arg k "${2}" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | if $paths | length > 0 then getpath($paths[-1]) else empty end
    ' "${1}"
}


# Sets a setting to a string, e.g. set_yaml_prop f server.host 0.0.0.0
function set_yaml_prop() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --arg v "${3}"
}

# Sets a setting to a JSON value, e.g. set_yaml_prop_json f opensearch.hosts '[]'
function set_yaml_prop_json() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --argjson v "${3}"
}

# Sets a setting to the list of the given items, one per argument,
# e.g. set_yaml_list f opensearch.hosts https://localhost:9200
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
