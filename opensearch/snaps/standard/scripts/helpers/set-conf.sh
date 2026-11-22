#!/usr/bin/env bash


function replace_in_file() {
    "${SNAP}"/usr/bin/setpriv \
        --reuid snap_daemon -- sed -i "s@${2}@${3}@" "${1}"
}

function remove_yaml_prop() {
    local target_file="${1}"
    local key_path="${2}"

    if [[ ${key_path} != ^.* ]]; then
        key_path=".${key_path}"
    fi
    "${SNAP}"/usr/bin/yq -y -i "del(${key_path})" "${target_file}"
}


function set_yaml_prop() {
    local target_file="${1}"
    local full_key_path="${2}"
    local value="${3}"
    local append="${4:-"no"}"
    local split_array_content="${5:-"yes"}"

    operator="="

    # allow appending
    if [ "${append}" == "yes" ]; then
        operator="+="
    fi

    # traversal must be done through the "/" separator to allow for "." in key names
    IFS='/' read -r -a keys <<< "${full_key_path}"

    expression=""
    for key in "${keys[@]}"
    do
        prefix=""
        suffix=""
        if [[ "${key}" != [* ]]; then
            prefix=".\""
            suffix="\""
        fi
        expression="${expression}${prefix}${key}${suffix}"
    done

    # yq fails serializing values starting with or containing special characters so they must be wrapped in double quotes
    # so, wrap any non number
    if [[ "${value}" == [* ]]; then
        value=${value:1:-1}

        if [ "${split_array_content}" == "yes" ]; then
            IFS=',' read -r -a arr_elts <<< "${value}"

            value=""
            for key in "${arr_elts[@]}"
            do
                key=$(echo -e "${key}" | tr -d '[:space:]')
                if ! [[ ${key} =~ ^[0-9]+$ ]] && ! [[ ${key} =~ ^\".*\"$ ]]; then
                    key="\"${key}\""
                fi
                value="${value}${key},"
            done
            value="[${value:0:-1}]"
        else
            value="[${value}]"
        fi
    elif ! [[ "${value}" =~ ^[0-9]+$ ]]  && ! [[ ${value} =~ ^\".*\"$ ]]; then
       value="\"${value}\""
    fi
    "${SNAP}"/usr/bin/yq -y -i "${expression} ${operator} ${value}" "${target_file}"
}


function edit_yaml_setting() {
    local target_file="${1}" key="${2}" operation="${3}"
    shift 3
    "${SNAP}"/usr/bin/yq -y -i --arg k "${key}" "$@" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | (if $paths | length > 0 then getpath($paths[-1]) else null end) as $old
        | delpaths($paths)
        | '"${operation}" "${target_file}"
}

# Sets a setting to a string, e.g. set_yaml_setting f cluster.name "a,b"
function set_yaml_setting() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --arg v "${3}"
}

# Sets a setting to a JSON value, e.g. set_yaml_setting_json f node.roles '[]'
function set_yaml_setting_json() {
    edit_yaml_setting "${1}" "${2}" '.[$k] = $v' --argjson v "${3}"
}

# Removes every spelling of a setting
function remove_yaml_setting() {
    edit_yaml_setting "${1}" "${2}" '.'
}

# Read the effective spelling, including nested and dotted settings.
function get_yaml_prop() {
    "${SNAP}"/usr/bin/yq -r --arg k "${2}" '
        [paths | select(all(.[]; type == "string") and join(".") == $k)] as $paths
        | if $paths | length > 0 then getpath($paths[-1]) else empty end
    ' "${1}"
}

function set_yaml_list() {
    local target_file="${1}" key="${2}" item
    shift 2
    set_yaml_setting_json "${target_file}" "${key}" '[]'
    for item in "$@"; do
        add_yaml_list_item "${target_file}" "${key}" "${item}"
    done
}

# Keep peer DNs intact when renewing this node's certificate.
function add_yaml_list_item() {
    edit_yaml_setting "${1}" "${2}" \
        '.[$k] = (($old // []) | (if type == "array" then . else [.] end)
                   | if any(.[]; . == $v) then . else . + [$v] end)' --arg v "${3}"
}


#function set_python_prop () {
#    python3 \
#        "${OPS_ROOT}"/helpers/conf-setter.py \
#        --file "${1}" \
#        --key "${2}" \
#        --value "${3}" \
#        --output "persist"
#}
