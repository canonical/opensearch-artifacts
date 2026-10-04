#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/io.sh
source "${OPS_ROOT}"/helpers/config.sh


usage() {
cat << EOF
usage: sudo ${SNAP_INSTANCE_NAME}.setup [-E<SETTING>=<VALUE> ...] [HOST ...]

Configures OpenSearch Dashboards and restarts it. Settings are written to:
  ${OSD_CONF_FILE}

<SETTING> follows the upstream OpenSearch Dashboards tarball conventions:
  - a configuration key, as passed to bin/opensearch-dashboards --<key>=<value>
      e.g. -Eserver.host=0.0.0.0 -Eopensearch.ssl.verificationMode=full
  - the upstream docker environment variable of a key
      e.g. -ESERVER_HOST=0.0.0.0 -EOPENSEARCH_USERNAME=kibanaserver
  - the same variable without its OPENSEARCH_ prefix
      e.g. -EUSERNAME=kibanaserver -EPASSWORD=kibanaserver

Special settings:
  -EHOSTS=<host> [<host> ...]
        OpenSearch hosts (opensearch.hosts). Further positional arguments and
        comma separated values are added to the list. The scheme defaults to
        https:// and the port to 9200.
  -ECA=<PEM>
        PEM content of the CA that signed the OpenSearch HTTP certificates,
        e.g. -ECA="\$(cat /path/to/root-ca.pem)". It is stored in
        ${OSD_CA_FILE} and trusted for
        connections to OpenSearch (verificationMode "certificate" unless set).

Values are written as strings, except true/false, integers and [a, b] lists.
Wrap a value in double quotes to force a string, e.g. -EPASSWORD='"1234"'.

  -h, --help    Shows this help menu
EOF
}


function die () {
    echo "error: ${*}" >&2
    exit 1
}


# Upstream settings exposed as environment variables by the docker image
# (src/dev/build/tasks/os_packages/docker_generator/.../opensearch-dashboards-docker),
# completed with the security plugin settings shipped in the default config.
OSD_SETTINGS=(
    console.enabled console.proxyConfig console.proxyFilter
    ops.cGroupOverrides.cpuPath ops.cGroupOverrides.cpuAcctPath
    cpu.cgroup.path.override cpuacct.cgroup.path.override
    csp.rules csp.strict csp.warnLegacyBrowsers
    data.search.usageTelemetry.enabled
    opensearch.customHeaders opensearch.hosts opensearch.logQueries
    opensearch.memoryCircuitBreaker.enabled
    opensearch.memoryCircuitBreaker.maxPercentage
    opensearch.password opensearch.pingTimeout
    opensearch.requestHeadersWhitelist opensearch.requestTimeout
    opensearch.shardTimeout opensearch.sniffInterval
    opensearch.sniffOnConnectionFault opensearch.sniffOnStart
    opensearch.ssl.alwaysPresentCertificate opensearch.ssl.certificate
    opensearch.ssl.certificateAuthorities opensearch.ssl.key
    opensearch.ssl.keyPassphrase opensearch.ssl.keystore.path
    opensearch.ssl.keystore.password opensearch.ssl.truststore.path
    opensearch.ssl.truststore.password opensearch.ssl.verificationMode
    opensearch.username opensearch.disablePrototypePoisoningProtection
    i18n.locale interpreter.enableInVisualize
    opensearchDashboards.autocompleteTerminateAfter
    opensearchDashboards.autocompleteTimeout
    opensearchDashboards.defaultAppId opensearchDashboards.index
    logging.dest logging.ignoreEnospcError logging.json logging.quiet
    logging.rotate.enabled logging.rotate.everyBytes logging.rotate.keepFiles
    logging.rotate.pollingInterval logging.rotate.usePolling logging.silent
    logging.useUTC logging.verbose
    map.includeOpenSearchMapsService map.proxyOpenSearchMapsServiceInMaps
    map.regionmap map.tilemap.options.attribution map.tilemap.options.maxZoom
    map.tilemap.options.minZoom map.tilemap.options.subdomains map.tilemap.url
    migrations.delete.enabled migrations.delete.types
    newsfeed.enabled ops.interval path.data pid.file regionmap
    security.showInsecureClusterWarning
    server.basePath server.compression.enabled
    server.compression.referrerWhitelist server.cors server.cors.origin
    server.defaultRoute server.host server.keepAliveTimeout
    server.maxPayloadBytes server.name server.port server.rewriteBasePath
    server.socketTimeout server.ssl.cert server.ssl.certificate
    server.ssl.certificateAuthorities server.ssl.cipherSuites
    server.ssl.clientAuthentication server.customResponseHeaders
    server.ssl.enabled server.ssl.key server.ssl.keyPassphrase
    server.ssl.keystore.path server.ssl.keystore.password
    server.ssl.truststore.path server.ssl.truststore.password
    server.ssl.redirectHttpFromPort server.ssl.supportedProtocols
    server.xsrf.disableProtection server.xsrf.whitelist
    status.allowAnonymous status.v6ApiFormat
    telemetry.allowChangingOptInStatus telemetry.enabled telemetry.optIn
    telemetry.optInStatusUrl telemetry.sendUsageFrom
    vega.enableExternalUrls vis_builder.enabled
    data_source.enabled data_source.audit.enabled
    opensearch_security.auth.type
    opensearch_security.cookie.secure
    opensearch_security.multitenancy.enabled
    opensearch_security.multitenancy.tenants.preferred
    opensearch_security.readonly_mode.roles
)


# Resolve a -E name into a configuration key.
function resolve_key () {
    local name="${1}"
    local candidate

    # A configuration key, used verbatim like the upstream --<key>=<value>.
    if [[ "${name}" == *.* ]]; then
        echo "${name}"
        return
    fi

    for candidate in "${name}" "OPENSEARCH_${name}"; do
        for key in "${OSD_SETTINGS[@]}"; do
            if [ "$(echo "${key^^}" | tr . _)" == "${candidate}" ]; then
                echo "${key}"
                return
            fi
        done
    done

    die "unknown setting '${name}', see --help"
}


# Convert a command line value into JSON, mirroring the yaml typing.
function to_json () {
    local value="${1}"
    local elements=()
    local element

    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
        jq -n --arg v "${BASH_REMATCH[1]}" '$v'
    elif [[ "${value}" =~ ^(true|false|-?[0-9]+)$ ]]; then
        echo "${value}"
    elif [[ "${value}" =~ ^\[(.*)\]$ ]]; then
        IFS=',' read -r -a elements <<< "${BASH_REMATCH[1]}"
        for element in "${elements[@]}"; do
            element="$(echo "${element}" | xargs)"
            [ -n "${element}" ] && to_json "${element}"
        done | jq -s -c '.'
    else
        jq -n --arg v "${value}" '$v'
    fi
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
        [ -n "${host}" ] && opensearch_hosts+=("$(normalize_host "${host}")")
    done
    return 0
}


# Args
declare -A settings=()
declare -a settings_order=()
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
        CA)
            [ -n "${value}" ] || die "-ECA requires the PEM content of the CA"
            ca_content="${value}"
            last_key=""
            return
            ;;
        HOSTS)
            key="opensearch.hosts"
            ;;
        *)
            key="$(resolve_key "${name}")"
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
        [ -n "${settings[${key}]+x}" ] || settings_order+=("${key}")
        settings["${key}"]="$(to_json "${value}")"
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
        die "-EHOSTS requires at least one host"
    fi
}


function install_ca () {
    local tmp_ca

    tmp_ca="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}")"
    printf '%s\n' "${ca_content}" > "${tmp_ca}"

    if ! openssl x509 -in "${tmp_ca}" -noout 2>/dev/null; then
        rm -f "${tmp_ca}"
        die "-ECA is not a valid PEM certificate"
    fi

    mv "${tmp_ca}" "${OSD_CA_FILE}"
    set_access_restrictions "${OSD_CA_FILE}" 660
    echo "Stored the OpenSearch CA in ${OSD_CA_FILE}:"
    openssl x509 -in "${OSD_CA_FILE}" -noout -subject -enddate
}


function write_config () {
    local tmp_conf key mode

    tmp_conf="$(mktemp -p "${OPENSEARCH_DASHBOARDS_PATH_CONF}")"
    cp "${OSD_CONF_FILE}" "${tmp_conf}"

    if [ -n "${ca_content}" ]; then
        set_conf_json "${tmp_conf}" "opensearch.ssl.certificateAuthorities" \
            "$(jq -n -c --arg v "${OSD_CA_FILE}" '[$v]')"

        # Verify the OpenSearch certificates against the CA, unless a stricter
        # mode was already configured.
        mode="$(yq -r '."opensearch.ssl.verificationMode" // "none"' "${tmp_conf}")"
        if [ "${mode}" == "none" ]; then
            set_conf_json "${tmp_conf}" "opensearch.ssl.verificationMode" \
                '"certificate"'
        fi
    fi

    if [ "${hosts_set}" == "yes" ]; then
        set_conf_json "${tmp_conf}" "opensearch.hosts" \
            "$(printf '%s\n' "${opensearch_hosts[@]}" | jq -R . | jq -s -c .)"
    fi

    for key in "${settings_order[@]}"; do
        set_conf_json "${tmp_conf}" "${key}" "${settings[${key}]}"
    done

    mv "${tmp_conf}" "${OSD_CONF_FILE}"
    set_access_restrictions "${OSD_CONF_FILE}" 660
}


parse_args "$@"

[ "$(id -u)" -eq 0 ] || die "must be run as root: sudo ${SNAP_INSTANCE_NAME}.setup"

if [ ! -d "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" ]; then
    mkdir -p "${OPENSEARCH_DASHBOARDS_PATH_CERTS}"
    set_access_restrictions "${OPENSEARCH_DASHBOARDS_PATH_CERTS}" 770
fi

[ -z "${ca_content}" ] || install_ca
write_config

echo "Updated ${OSD_CONF_FILE}"
service="${SNAP_INSTANCE_NAME}.opensearch-dashboards-daemon"
if snapctl restart "${service}"; then
    echo "Restarted ${service}"
else
    echo "warning: could not restart, run: sudo snap restart ${service}" >&2
fi
