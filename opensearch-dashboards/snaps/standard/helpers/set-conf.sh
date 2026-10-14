#!/usr/bin/env bash

# Same helpers as the OpenSearch snap (opensearch/snaps/standard/scripts/helpers/set-conf.sh).


# A setting can be spelled dotted ("opensearch.hosts"), nested or mixed: replace every
# spelling by a single dotted key. Upstream assigns a nested key ("opensearch:") over the
# dotted keys read before it, so a parent emptied here is removed too.
function edit_yaml_setting() {
    local target_file="${1}" key="${2}" operation="${3}"
    shift 3
    "${SNAP}"/usr/bin/yq -y -i --arg k "${key}" "$@" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | delpaths($paths)
        | reduce ($paths[] | range(length - 1; 0; -1) as $n | .[:$n]) as $parent
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

# Sets a setting to a JSON value, e.g. set_yaml_prop_json f opensearch.hosts '["https://a:9200"]'
function set_yaml_prop_json() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --argjson v "${3}"
}

function remove_yaml_prop() {
    edit_yaml_setting "${1}" "${2}" '.'
}
