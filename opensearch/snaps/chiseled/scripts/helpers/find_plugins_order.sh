#!/usr/bin/env bash
#
# Compute the dependency-safe removal order for OpenSearch plugins.
#
# OpenSearch plugins declare "extended.plugins" in their
# plugin-descriptor.properties. A plugin that extends another cannot
# be removed before the extending plugin is removed. This script
# performs a topological sort (Kahn's algorithm) to produce an order
# in which plugins can be safely removed — dependents first, then
# their dependencies.
#
# Usage:
#   find_plugins_order.sh [OPTIONS] <path>
#
# <path> can be:
#   - An extracted OpenSearch directory (containing plugins/)
#   - A plugins/ directory directly
#   - A .tar.gz tarball of an OpenSearch distribution
#
# Options:
#   -e, --essential PLUGIN   Plugin to keep (repeatable).
#                            Default: opensearch-security
#   -h, --help               Show this help message
#
# Example:
#   ./find_plugins_order.sh /tmp/opensearch-3.7.0
#   ./find_plugins_order.sh opensearch-3.7.0-linux-x64.tar.gz
#   ./find_plugins_order.sh -e opensearch-security /path/to/plugins
#
# Output:
#   Prints a bash array ready to paste into snapcraft.yaml's
#   plugins_to_remove list, preceded by a summary header.

set -euo pipefail

readonly script_name="$(basename "${0}")"

essential_plugins=()
all_plugins=()
removal_order=()
plugins_dir=""
cleanup_tmpdir=""


usage() {
    sed -n '2,/^$/p' "${0}" | sed 's/^# \?//'
    exit 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -e|--essential)
                essential_plugins+=("$2")
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done

    if [ $# -lt 1 ]; then
        echo "Error: missing <path> argument" >&2
        echo "Run '${script_name} --help' for usage." >&2
        exit 1
    fi

    input_path="$1"
}

resolve_plugins_dir() {
    local path="$1"

    if [ ! -e "${path}" ]; then
        echo "Error: path does not exist: ${path}" >&2
        exit 1
    fi

    case "${path}" in
        *.tar.gz|*.tgz)
            local tmpdir
            tmpdir="$(mktemp -d)"
            tar -xzf "${path}" -C "${tmpdir}"
            plugins_dir="$(find "${tmpdir}" -type d -name plugins | head -1)"
            if [ -z "${plugins_dir}" ]; then
                echo "Error: no plugins/ directory found in tarball" >&2
                rm -rf "${tmpdir}"
                exit 1
            fi
            cleanup_tmpdir="${tmpdir}"
            ;;
        *)
            if [ -d "${path}/plugins" ]; then
                plugins_dir="${path}/plugins"
            elif [ "$(basename "${path}")" = "plugins" ] && [ -d "${path}" ]; then
                plugins_dir="${path}"
            else
                echo "Error: no plugins/ directory found under: ${path}" >&2
                exit 1
            fi
            ;;
    esac
}

compute_removal_order() {
    if [ -z "${essential_plugins+x}" ] || [ ${#essential_plugins[@]} -eq 0 ]; then
        essential_plugins=("opensearch-security")
    fi

    declare -A installed_set=()
    declare -A extended_by_map=()

    all_plugins=()
    removal_order=()

    while IFS= read -r descriptor; do
        plugin_name=$(basename "$(dirname "${descriptor}")")
        all_plugins+=("${plugin_name}")
        installed_set["${plugin_name}"]=1
    done < <(find "${plugins_dir}" -mindepth 2 -maxdepth 2 -name "plugin-descriptor.properties")

    if [ ${#all_plugins[@]} -eq 0 ]; then
        echo "Error: no plugins found in ${plugins_dir}" >&2
        exit 1
    fi

    for p in "${all_plugins[@]}"; do
        descriptor="${plugins_dir}/${p}/plugin-descriptor.properties"
        extended_string=$(grep -E "^extended.plugins=" "${descriptor}" 2>/dev/null | cut -d'=' -f2- || true)
        if [ -n "${extended_string}" ]; then
            IFS=',' read -ra extended_arr <<< "${extended_string}"
            for ext in "${extended_arr[@]}"; do
                ext_name="${ext%%;*}"
                ext_name="$(echo "${ext_name}" | xargs)"
                if [ -n "${ext_name}" ] && [ "${installed_set[${ext_name}]:-0}" = "1" ]; then
                    extended_by_map["${ext_name}"]+="${p} "
                fi
            done
        fi
    done

    declare -A removed=()
    remaining=${#all_plugins[@]}

    while [ "${remaining}" -gt 0 ]; do
        progress=0
        for p in "${all_plugins[@]}"; do
            [ -n "${removed[${p}]:-}" ] && continue

            is_essential=false
            for essential in "${essential_plugins[@]}"; do
                [ "${p}" = "${essential}" ] && { is_essential=true; break; }
            done
            if [ "${is_essential}" = "true" ]; then
                removed["${p}"]=1
                remaining=$((remaining - 1))
                progress=1
                continue
            fi

            blocked=false
            for dep in ${extended_by_map["${p}"]:-}; do
                if [ -z "${removed[${dep}]:-}" ]; then
                    blocked=true
                    break
                fi
            done
            if [ "${blocked}" = "false" ]; then
                removal_order+=("${p}")
                removed["${p}"]=1
                remaining=$((remaining - 1))
                progress=1
            fi
        done
        if [ "${progress}" -eq 0 ]; then
            echo "Error: dependency cycle detected among plugins; aborting" >&2
            exit 1
        fi
    done
}

print_result() {
    local total=${#all_plugins[@]}
    local to_remove=${#removal_order[@]}
    local kept=$((total - to_remove))

    echo "# Dependency-safe plugin removal order"
    echo "# Total plugins found: ${total}"
    echo "# Plugins to remove:   ${to_remove}"
    echo "# Plugins kept:        ${kept} (${essential_plugins[*]})"
    echo "#"
    echo "# Paste this array into snapcraft.yaml's plugins_to_remove list."
    echo "# Regenerate when the OpenSearch version is bumped."
    echo ""
    echo 'declare -a plugins_to_remove=('
    for p in "${removal_order[@]}"; do
        echo "    \"${p}\""
    done
    echo ')'
}

main() {
    parse_args "$@"
    resolve_plugins_dir "${input_path}"
    compute_removal_order
    print_result

    if [ -n "${cleanup_tmpdir}" ]; then
        rm -rf "${cleanup_tmpdir}"
    fi
}

main "$@"
