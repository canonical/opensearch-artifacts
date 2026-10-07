#!/usr/bin/env bash

set -e -o pipefail

# Bundled plugins belong to the snap. Reject removal before the native tool or
# configuration helper can change their links, files or saved configuration.
check_bundled_removal() {
    local argument subcommand="" parse_options=true setting_value_follows=false
    local plugins_dir shipped_dir target plugin_name
    local -a operands=()

    # Find the removal target, keeping native help, -E settings and option order usable.
    for argument in "$@"; do
        if "$setting_value_follows"; then
            setting_value_follows=false
            continue
        fi
        if "$parse_options"; then
            case "$argument" in
                -) ;;  # A lone dash is a plugin name, not an option.
                --) parse_options=false; continue ;;
                --h|--he|--hel|--help) return 0 ;;
                -*)
                    # A grouped help flag is harmless; an h inside an -E value is not help.
                    [[ "$argument" =~ ^-[psv]*h ]] && return 0
                    if [[ "$argument" = --E || "$argument" =~ ^-[psv]*E$ ]]; then
                        setting_value_follows=true
                    fi
                    continue ;;
            esac
        fi
        # The top-level command and remove each parse their own options after --.
        if [ -z "$subcommand" ]; then
            [ "$argument" = remove ] || return 0
            subcommand=remove
            parse_options=true
        else
            operands+=("$argument")
        fi
    done

    # Native removal accepts exactly one plugin. Leave malformed invocations to its parser.
    [ "${#operands[@]}" -eq 1 ] || return 0
    argument="${operands[0]}"
    plugins_dir="$(readlink -f -- "${SNAP_DATA}/usr/share/opensearch/plugins")"
    shipped_dir="$(readlink -f -- "${SNAP}/usr/share/opensearch/shipped-plugins")"
    plugin_name="$(basename -- "$argument")"
    target="$argument"
    [[ "$target" = /* ]] || target="${plugins_dir}/${target}"
    target="$(readlink -m -- "$target")"

    # The immutable inventory also protects missing links. Resolve aliases and parent paths
    # so another spelling cannot make native removal delete bundled plugins indirectly.
    if [ -f "${shipped_dir}/${plugin_name}/plugin-descriptor.properties" ] ||
       [[ "$target/" = "$shipped_dir/"* || "$plugins_dir/" = "${target%/}/"* ]]; then
        echo "Plugin '$argument' is bundled with this snap and cannot be removed. No changes were made." >&2
        echo "Use the opensearch-chiseled snap if you need to choose which plugins are installed." >&2
        return 64
    fi
}

check_bundled_removal "$@"

if [ -z "${OPENSEARCH_JAVA_OPTS:-}" ]; then
    export OPENSEARCH_JAVA_OPTS="-Xms1g -Xmx1g"
fi

# Run the native tool and update this revision's saved configuration after removal.
# Other revisions keep their own copies for rollback. The root group is needed:
# the installer copies the config's owner and group (snap_daemon:root) onto new files.
exec "${SNAP}/usr/bin/setpriv" \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    "${SNAP}/usr/bin/python3" "${SNAP}/opt/opensearch/helpers/plugin-configuration.py" \
    run "${OPENSEARCH_BIN}/opensearch-plugin" "${@}"
