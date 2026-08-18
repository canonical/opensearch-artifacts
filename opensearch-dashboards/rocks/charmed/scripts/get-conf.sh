#!/usr/bin/env bash


function get_yaml_prop() {
    local target_file="${1}"
    local full_key_path="${2}"
    local default="${3}"

    # -r (raw) is required: without it yq emits JSON-quoted scalars, so a
    # port would come back as "5601" (quotes included) and end up inside
    # the exporter URL.
    /usr/bin/yq -r ".\"${full_key_path}\" // \"${default}\"" "${target_file}"
}
