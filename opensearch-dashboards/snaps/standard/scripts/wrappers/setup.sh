#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/io.sh
source "${OPS_ROOT}"/helpers/config.sh


usage() {
cat << EOF
usage: sudo opensearch-dashboards.setup [-E<SETTING>=<VALUE> ...] [HOST ...]

Configures OpenSearch Dashboards and restarts it. Settings are written to:
  ${OSD_CONF_FILE}

<SETTING> is one of the following upstream configuration keys, as in
opensearch_dashboards.yml, e.g. -Eserver.host=0.0.0.0:

  opensearch.hosts
  opensearch.username
  opensearch.password
  opensearch.ssl.verificationMode
  opensearch.requestTimeout
  server.host
  server.port
  server.name
  server.basePath
  opensearch_security.multitenancy.enabled

Any other setting is edited directly in the configuration file.

Special settings:
  -EOPENSEARCH_HOSTS=<host> [<host> ...]
        OpenSearch hosts (opensearch.hosts). Further positional arguments and
        comma separated values are added to the list. The scheme defaults to
        https:// and the port to 9200.
  -EOPENSEARCH_CA=<PEM>
        PEM content of the CA that signed the OpenSearch HTTP certificates,
        e.g. -EOPENSEARCH_CA="\$(cat /path/to/root-ca.pem)". It is stored in
        ${OSD_CA_FILE} and trusted for
        connections to OpenSearch (verificationMode "full" unless set: the
        OpenSearch certificates must also be valid for the hosts used).

As in the OpenSearch snap, the value is written as is, as a string: OpenSearch
Dashboards converts it to the type of the setting, e.g. -Eserver.port=5602.
A value in brackets is a YAML list. An empty value removes the setting,
e.g. -Eserver.name=

  -h, --help    Shows this help menu
EOF
}


function die () {
    echo "error: ${*}" >&2
    exit 1
}


# The most used settings, see the upstream opensearch_dashboards.yml. Others
# are edited directly in the configuration file.
OSD_SETTINGS=(
    opensearch.hosts
    opensearch.username
    opensearch.password
    opensearch.ssl.verificationMode
    opensearch.requestTimeout
    server.host
    server.port
    server.name
    server.basePath
    opensearch_security.multitenancy.enabled
)


function check_supported () {
    local key

    for key in "${OSD_SETTINGS[@]}"; do
        [ "${key}" != "${1}" ] || return 0
    done
    die "unsupported setting '${1}', see --help"
}


# As in the OpenSearch snap, a value in brackets is a YAML list, converted
# here to JSON for jq.
function yaml_list_to_json () {
    local key="${1}" value="${2}" json

    if ! json="$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -c '.' 2>/dev/null)" \
            || [ "$(printf '%s' "${json}" | jq -r 'type')" != "array" ]; then
        die "'${value}' of ${key} is not a valid YAML list"
    fi
    echo "${json}"
}


# https://localhost:9200 from localhost, 10.0.0.1:9201 or http://[::1]
function normalize_host () {
    local host="${1}"
    local scheme="https://"
    local authority

    if [[ "${host}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)(.*)$ ]]; then
        scheme="${BASH_REMATCH[1]}"
        host="${BASH_REMATCH[2]}"
    fi
    host="${host%/}"
    authority="${host%%/*}"

    # bare IPv6 address
    if [[ "${authority}" == *:*:* ]] && [[ "${authority}" != \[* ]]; then
        host="[${authority}]${host#"${authority}"}"
        authority="[${authority}]"
    fi

    if ! [[ "${authority}" =~ :[0-9]+$ ]]; then
        host="${authority}:9200${host#"${authority}"}"
    fi

    echo "${scheme}${host}"
}


function add_hosts () {
    local hosts=()
    local host

    IFS=', ' read -r -a hosts <<< "${1}"
    for host in "${hosts[@]}"; do
        [ -n "${host}" ] || continue
        host="$(normalize_host "${host}")"
        [[ " ${opensearch_hosts[*]} " == *" ${host} "* ]] || opensearch_hosts+=("${host}")
    done
}


# Args
declare -a keys=() kinds=() values=()
declare -a opensearch_hosts=()
hosts_set="no"
ca_content=""
last_key=""


function add_setting () {
    local arg="${1}"
    local name value key

    [[ "${arg}" == *=* ]] || die "expected -E<SETTING>=<VALUE>, got '-E${arg}'"
    name="${arg%%=*}"
    value="${arg#*=}"

    case "${name}" in
        OPENSEARCH_CA)
            [ -n "${value}" ] || die "-EOPENSEARCH_CA requires the PEM content of the CA"
            ca_content="${value}"
            last_key=""
            return
            ;;
        OPENSEARCH_HOSTS)
            key="opensearch.hosts"
            ;;
        *)
            check_supported "${name}"
            key="${name}"
            ;;
    esac

    if [ "${key}" == "opensearch.hosts" ]; then
        hosts_set="yes"
        opensearch_hosts=()
        if [[ "${value}" =~ ^\[(.*)\]$ ]]; then
            value="${BASH_REMATCH[1]//\"/}"
        fi
        add_hosts "${value}"
    else
        keys+=("${key}")
        if [ -z "${value}" ]; then
            kinds+=("remove")
        elif [[ "${value}" == \[*\] ]]; then
            kinds+=("list")
            value="$(yaml_list_to_json "${key}" "${value}")"
        else
            kinds+=("string")
        fi
        values+=("${value}")
    fi
    last_key="${key}"
}


function parse_args () {
    [ $# -gt 0 ] || { usage; exit 1; }

    while [ $# -gt 0 ]; do
        case "${1}" in
            -h|--help)
                usage
                exit 0
                ;;
            -E)
                shift
                [ $# -gt 0 ] || die "-E requires <SETTING>=<VALUE>"
                add_setting "${1}"
                ;;
            -E*)
                add_setting "${1#-E}"
                ;;
            -*)
                die "unknown option '${1}', see --help"
                ;;
            *)
                [ "${last_key}" == "opensearch.hosts" ] || \
                    die "unexpected argument '${1}', see --help"
                add_hosts "${1}"
                ;;
        esac
        shift
    done

    if [ "${hosts_set}" == "yes" ] && [ ${#opensearch_hosts[@]} -eq 0 ]; then
        die "-EOPENSEARCH_HOSTS requires at least one host"
    fi
}


function install_ca () {
    local tmp_ca

    tmp_ca="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}")"
    printf '%s\n' "${ca_content}" > "${tmp_ca}"

    # Only parse the certificate: the system CA bundle, which openssl loads by
    # default, is unused and not readable by this app.
    if ! SSL_CERT_FILE=/dev/null openssl x509 -in "${tmp_ca}" -noout 2>/dev/null; then
        rm -f "${tmp_ca}"
        die "-EOPENSEARCH_CA is not a valid PEM certificate"
    fi

    mv "${tmp_ca}" "${OSD_CA_FILE}"
    set_access_restrictions "${OSD_CA_FILE}" 660
    echo "Stored the OpenSearch CA in ${OSD_CA_FILE}:"
    SSL_CERT_FILE=/dev/null openssl x509 -in "${OSD_CA_FILE}" -noout -subject -enddate
}


function write_config () {
    local tmp_conf i mode

    tmp_conf="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CONF}")"
    cp "${OSD_CONF_FILE}" "${tmp_conf}"

    if [ -n "${ca_content}" ]; then
        set_yaml_prop_json "${tmp_conf}" "opensearch.ssl.certificateAuthorities" \
            "$(jq -cn --arg v "${OSD_CA_FILE}" '[$v]')"

        # Verify the OpenSearch certificates against the CA and the host names,
        # unless a verification mode was already chosen.
        mode="$(get_yaml_prop "${tmp_conf}" "opensearch.ssl.verificationMode")"
        if [ "${mode:-none}" == "none" ]; then
            set_yaml_prop "${tmp_conf}" "opensearch.ssl.verificationMode" "full"
        fi
    fi

    if [ "${hosts_set}" == "yes" ]; then
        set_yaml_prop_json "${tmp_conf}" "opensearch.hosts" \
            "$(jq -cn '$ARGS.positional' --args "${opensearch_hosts[@]}")"
    fi

    for i in "${!keys[@]}"; do
        case "${kinds[i]}" in
            remove) remove_yaml_prop "${tmp_conf}" "${keys[i]}" ;;
            list)   set_yaml_prop_json "${tmp_conf}" "${keys[i]}" "${values[i]}" ;;
            string) set_yaml_prop "${tmp_conf}" "${keys[i]}" "${values[i]}" ;;
        esac
    done

    mv "${tmp_conf}" "${OSD_CONF_FILE}"
    set_access_restrictions "${OSD_CONF_FILE}" 660
}


parse_args "$@"

[ "$(id -u)" -eq 0 ] || die "must be run as root: sudo opensearch-dashboards.setup"

if [ ! -d "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" ]; then
    mkdir -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"
    set_access_restrictions "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" 770
fi

[ -z "${ca_content}" ] || install_ca
write_config

echo "Updated ${OSD_CONF_FILE}"
service="opensearch-dashboards.opensearch-dashboards-daemon"
if snapctl restart "${service}"; then
    echo "Restarted ${service}"
else
    echo "warning: could not restart, run: sudo snap restart ${service}" >&2
fi
