#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/io.sh
source "${OPS_ROOT}"/helpers/config.sh


usage() {
cat << EOF
usage: sudo opensearch-dashboards.setup [--<setting>=<value> ...] [HOST ...]

Configures OpenSearch Dashboards. Settings are written to:
  ${OSD_CONF_FILE}

--<setting>=<value>   Sets an OpenSearch Dashboards setting, as the upstream
                      bin/opensearch-dashboards --<setting>=<value>, e.g.
                      --server.host=0.0.0.0. The value is written as is, as a
                      string, which OpenSearch Dashboards converts to the type
                      of the setting, e.g. --server.port=5602. A value in
                      brackets is a YAML list. An empty value removes the
                      setting, e.g. --server.name=
                      OpenSearch Dashboards refuses to start with an unknown
                      setting: check the logs after a change.

--opensearch.hosts=<host> [<host> ...]
        OpenSearch hosts. Further positional arguments and comma separated
        values are added to the list. The scheme defaults to https:// and the
        port to 9200.

--opensearch-ca=<PEM>
        PEM content of the CA that signed the OpenSearch HTTP certificates,
        e.g. --opensearch-ca="\$(cat /path/to/root-ca.pem)", or of several
        CAs. It is stored in ${OSD_CA_FILE} and trusted for
        connections to OpenSearch
        (verificationMode "full" unless set: the OpenSearch certificates must
        also be valid for the hosts used).

  -h, --help    Shows this help menu

The daemon must be restarted for the new settings to be applied:
  sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon
EOF
}


function die () {
    echo "error: ${*}" >&2
    exit 1
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
# Temporary files of this run, removed on exit.
tmp_conf=""
tmp_ca_dir=""
tmp_ca=""


function add_setting () {
    local arg="${1}"
    local name value key items json

    name="${arg%%=*}"
    value="${arg#*=}"
    [[ "${arg}" == *=* ]] && [ -n "${name}" ] \
        || die "expected --<setting>=<value>, got '--${arg}'"

    case "${name}" in
        opensearch-ca)
            [ -n "${value}" ] || die "--opensearch-ca requires the PEM content of the CA"
            ca_content="${value}"
            last_key=""
            return
            ;;
        *)
            key="${name}"
            ;;
    esac

    if [ "${key}" == "opensearch.hosts" ]; then
        hosts_set="yes"
        opensearch_hosts=()
        if [[ "${value}" =~ ^\[(.*)\]$ ]]; then
            items="${BASH_REMATCH[1]}"
            # A YAML list, or a list of unquoted URLs, e.g. [https://[::1]:9200],
            # which is not valid YAML.
            if json="$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -c '.' 2>/dev/null)" \
                    && [ "$(jq -r 'type' <<< "${json}")" == "array" ]; then
                value="$(jq -r 'map(tostring) | join(",")' <<< "${json}")"
            else
                value="${items//\"/}"
            fi
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
            --?*)
                add_setting "${1#--}"
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
        die "--opensearch.hosts requires at least one host"
    fi
}


# Store the certificates of the PEM content, without anything else pasted along,
# e.g. a private key, after checking each of them.
function install_ca () {
    local line count=0 i in_cert="no"

    tmp_ca_dir="$(mktemp -d -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}")"
    while IFS= read -r line; do
        line="${line%"${line##*[![:space:]]}"}"
        if [ "${line}" = "-----BEGIN CERTIFICATE-----" ]; then
            count=$((count + 1))
            in_cert="yes"
        fi
        [ "${in_cert}" = "no" ] || printf '%s\n' "${line}" >> "${tmp_ca_dir}/${count}.pem"
        [ "${line}" != "-----END CERTIFICATE-----" ] || in_cert="no"
    done <<< "${ca_content}"

    [ "${count}" -gt 0 ] || die "--opensearch-ca is not a valid PEM certificate"
    # Only parse the certificates: the system CA bundle, which openssl loads by
    # default, is unused and not readable by this app.
    for ((i = 1; i <= count; i++)); do
        SSL_CERT_FILE=/dev/null openssl x509 -in "${tmp_ca_dir}/${i}.pem" -noout 2>/dev/null \
            || die "certificate ${i} of --opensearch-ca is not a valid PEM certificate"
    done

    tmp_ca="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}")"
    for ((i = 1; i <= count; i++)); do
        cat "${tmp_ca_dir}/${i}.pem" >> "${tmp_ca}"
    done
    mv "${tmp_ca}" "${OSD_CA_FILE}"
    set_access_restrictions "${OSD_CA_FILE}" 660

    echo "Stored the OpenSearch CA in ${OSD_CA_FILE}:"
    for ((i = 1; i <= count; i++)); do
        SSL_CERT_FILE=/dev/null openssl x509 -in "${tmp_ca_dir}/${i}.pem" -noout -subject -enddate \
            | sed 's/^/  /'
    done
}


function write_config () {
    local i mode

    tmp_conf="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CONF}")"
    if [ -f "${OSD_CONF_FILE}" ]; then
        cp "${OSD_CONF_FILE}" "${tmp_conf}"
    else
        echo "warning: ${OSD_CONF_FILE} is missing, the default configuration is restored" >&2
        cp "${SNAP}"/etc/opensearch-dashboards/opensearch_dashboards.yml "${tmp_conf}"
        set_default_settings "${tmp_conf}"
    fi

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


# Node.js does not match an IPv6 address with the IP addresses of a
# certificate, which verificationMode "full", the default when it is not set,
# requires.
function warn_ipv6_hosts () {
    local mode

    mode="$(get_yaml_prop "${OSD_CONF_FILE}" "opensearch.ssl.verificationMode")"
    if [ "${mode:-full}" == "full" ] \
            && get_yaml_prop "${OSD_CONF_FILE}" "opensearch.hosts" | grep -q '://\['; then
        echo "warning: the certificate of an IPv6 address of opensearch.hosts fails the" \
            "verification: use a host name, or --opensearch.ssl.verificationMode=certificate" >&2
    fi
}


function cleanup () {
    [ -z "${tmp_conf}" ] || rm -f -- "${tmp_conf}"
    [ -z "${tmp_ca_dir}" ] || rm -rf -- "${tmp_ca_dir}"
    [ -z "${tmp_ca}" ] || rm -f -- "${tmp_ca}"
}


parse_args "$@"

[ "$(id -u)" -eq 0 ] || die "must be run as root: sudo opensearch-dashboards.setup"

trap cleanup EXIT
# One run at a time: each one rewrites the whole configuration.
exec 9< "${OPENSEARCH_DASHBOARDS_PATH_CONF}"
flock 9

if [ ! -d "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" ]; then
    mkdir -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"
    set_access_restrictions "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" 770
fi

[ -z "${ca_content}" ] || install_ca
write_config
warn_ipv6_hosts

echo "Updated ${OSD_CONF_FILE}"
echo "Restart the daemon to apply: sudo snap restart opensearch-dashboards.opensearch-dashboards-daemon"
