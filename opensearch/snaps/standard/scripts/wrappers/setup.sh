#!/usr/bin/env bash

set -eu

usage() {
cat << EOF
usage: setup.sh -E <setting>=<value> [-E <setting>=<value> ...]
       setup.sh --node-name <name> [--<option> <value> ...]   (legacy)
Reconfigures this instance: every setting is written to opensearch.yml.
The two forms cannot be combined.

-E <setting>=<value>   Sets an OpenSearch setting, e.g. -Ecluster.name=my-cluster.
                       The value is written as is, as a string. As upstream,
                       list settings accept comma separated values,
                       e.g. -Enode.roles=cluster_manager,data
                       A value in brackets is a YAML list: quote entries that
                       contain commas, e.g.
                       -Eplugins.security.nodes_dn='["CN=a,OU=x","CN=b,OU=x"]'
                       -Enode.roles=[] makes a coordinating-only node.
                       An empty value removes the setting, e.g. -Ehttp.port=
--help                 Shows help menu

Legacy options, kept for compatibility with the previous revisions:
--cluster-name            (Optional)  Name of the cluster, default: opensearch-cluster
--node-name               (Required)  Name of the current node
--node-roles              (Optional)  Type of the node, array combination of: [cluster_manager, data, voting_only, ..]
--node-host               (Optional)  IP address used to bind the node, default: [ _local_, _site_ ]
--seed-hosts              (Optional)  Private IP of all the cluster-manager eligible nodes, default: ["127.0.0.1", "[::1]"]
--security-disabled       (Optional)  Enum of either yes, no (default). Enables or disables the security plugin.
--tls-self-managed        (Optional)  Enum of either yes (default), no. Generates and self-signs the certificates.
--tls-init-setup          (Optional)  Enum of either yes, no (default). Creates a root and admin certs if set to yes.
--tls-priv-key-root-pass  (Optional)  Password for encrypting the root key, required if --tls-self-managed is yes
--tls-root-subject        (Optional)  Subject for the root
--tls-priv-key-admin-pass (Optional)  Password for encrypting the admin key
--tls-admin-subject       (Optional)  Subject for the admin certificate
--tls-priv-key-node-pass  (Optional)  Password for encrypting the node key
--tls-node-subject        (Optional)  Subject for the node certificate
--tls-for-rest            (Optional)  Enum of either: yes (default), no. Enables the certificate for both the transport and rest layers or just the former

The daemon must be restarted for the new settings to be applied:
  snap restart opensearch.daemon

Examples:
  setup.sh -Ecluster.name=logs -Enode.name=node-1 \\
      -Enode.roles=cluster_manager,data \\
      -Enetwork.host=_local_,_site_ \\
      -Ediscovery.seed_hosts=10.0.0.1,10.0.0.2 \\
      -Ecluster.initial_cluster_manager_nodes=node-1

  # node joining another cluster: this node bootstrapped its own cluster on
  # install, its data must be removed first (see the README)
  setup.sh -Ediscovery.seed_hosts=10.0.0.1 -Ecluster.initial_cluster_manager_nodes=
EOF
}

# Handle --help argument before snap-logger
for arg in "$@"; do
    if [ "${arg}" == "--help" ]; then
        usage
        exit 0
    fi
done

# The configuration and the logs are only writable by root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: opensearch.setup must be run as root: sudo opensearch.setup $*" >&2
    exit 1
fi


# Sets mode to whether the arguments use the -E form or the legacy
# --<option> form, failing if both are used: the value following a separate
# '-E' or '--<option>' is skipped.
mode=""
function detect_mode () {
    local with_e="no" with_legacy="no"
    while [ $# -gt 0 ]; do
        case $1 in
            -E)
                with_e="yes"
                shift
                ;;
            -E*)
                with_e="yes"
                ;;
            --*=*)
                with_legacy="yes"
                ;;
            --*)
                with_legacy="yes"
                shift
                ;;
        esac
        [ $# -gt 0 ] && shift
    done

    if [ "${with_e}" == "yes" ] && [ "${with_legacy}" == "yes" ]; then
        echo "ERROR: -E <setting>=<value> and the legacy --<option> arguments cannot be used together. Refer to the help menu." >&2
        exit 1
    fi

    if [ "${with_legacy}" == "yes" ]; then
        mode="legacy"
    else
        mode="settings"
    fi
}


#### -E <setting>=<value> form ####

# Args
declare -a settings=()


# Args handling
function parse_settings_args() {
    local setting
    while [ $# -gt 0 ]; do
        case $1 in
            -E)
                shift
                if [ $# -eq 0 ]; then
                    echo "ERROR: -E requires a <setting>=<value> argument." >&2
                    exit 1
                fi
                setting="$1"
                ;;
            -E*)
                setting="${1#-E}"
                ;;
            *)
                echo "ERROR: unexpected argument '$1'. Settings are passed as -E <setting>=<value>." >&2
                exit 1
                ;;
        esac

        if [[ "${setting}" != *=* ]] || [ -z "${setting%%=*}" ]; then
            echo "ERROR: '${setting}' is not of the form <setting>=<value>." >&2
            exit 1
        fi
        settings+=("${setting}")

        shift
    done

    if [ "${#settings[@]}" -eq 0 ]; then
        echo "ERROR: at least one -E <setting>=<value> is required. Refer to the help menu." >&2
        exit 1
    fi
}


function setup_settings () {
    parse_settings_args "$@"

    # Validate every setting before writing any: values in brackets must be
    # YAML lists, converted here to JSON for jq.
    local setting key value kind i
    local -a keys=() kinds=() values=()
    for setting in "${settings[@]}"; do
        key="${setting%%=*}"
        value="${setting#*=}"
        if [ -z "${value}" ]; then
            kind="remove"
        elif [[ "${value}" == \[*\] ]]; then
            kind="list"
            if ! value="$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -c '.' 2>/dev/null)" \
                || [ "$(printf '%s' "${value}" | "${SNAP}"/usr/bin/yq -r 'type')" != "array" ]; then
                echo "ERROR: '${setting#*=}' of ${key} is not a valid YAML list." >&2
                echo "Quote entries that contain commas, e.g. -E${key}='[\"CN=a,OU=x\"]'" >&2
                exit 1
            fi
        else
            kind="string"
        fi
        keys+=("${key}")
        kinds+=("${kind}")
        values+=("${value}")
    done

    # Tell users what values we are using for the configuration
    echo "Configuring OpenSearch with the following values:"
    for i in "${!keys[@]}"; do
        case "${kinds[i]}" in
            remove) echo "${keys[i]}: (removed)" ;;
            *)      echo "${keys[i]}: ${values[i]}" ;;
        esac
    done


    source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
    source "${OPS_ROOT}"/helpers/set-conf.sh

    local opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
    for i in "${!keys[@]}"; do
        case "${kinds[i]}" in
            remove) remove_yaml_prop "${opensearch_yaml}" "${keys[i]}" ;;
            list)   set_yaml_prop_json "${opensearch_yaml}" "${keys[i]}" "${values[i]}" ;;
            string) set_yaml_prop "${opensearch_yaml}" "${keys[i]}" "${values[i]}" ;;
        esac
    done
}


#### Legacy --<option> <value> form ####

# Args
cluster_name=""
node_name=""
node_roles=""
node_host=""
seed_hosts=""
initial_cluster_manager_nodes=""

security_disabled=""

tls_self_managed=""
tls_init_setup=""
tls_priv_key_root_pass=""
tls_root_subject=""
tls_priv_key_admin_pass=""
tls_admin_subject=""
tls_priv_key_node_pass=""
tls_node_subject=""
tls_for_rest=""

# Args handling
function parse_legacy_args() {
    local LONG_OPTS_LIST=(
        "cluster-name"
        "node-name"
        "node-roles"
        "node-host"
        "seed-hosts"
        "security-disabled"
        "tls-self-managed"
        "tls-init-setup"
        "tls-priv-key-root-pass"
        "tls-root-subject"
        "tls-priv-key-admin-pass"
        "tls-admin-subject"
        "tls-priv-key-node-pass"
        "tls-node-subject"
        "tls-for-rest"
    )
    local opts
    if ! opts=$(getopt \
      --longoptions "$(printf "%s:," "${LONG_OPTS_LIST[@]}")" \
      --name "opensearch.setup" \
      --options "" \
      -- "$@"
    ); then
        echo "Refer to the help menu." >&2
        exit 1
    fi
    eval set -- "${opts}"

    while [ $# -gt 0 ]; do
        case $1 in
            --cluster-name) shift
                cluster_name=$1
                ;;
            --node-name) shift
                node_name=$1
                ;;
            --node-roles) shift
                node_roles=$1
                ;;
            --node-host) shift
                node_host=$1
                ;;
            --seed-hosts) shift
                seed_hosts=$1
                ;;
            --security-disabled) shift
                security_disabled=$1
                ;;
            --tls-self-managed) shift
                tls_self_managed=$1
                ;;
            --tls-init-setup) shift
                tls_init_setup=$1
                ;;
            --tls-priv-key-root-pass) shift
                tls_priv_key_root_pass=$1
                ;;
            --tls-priv-key-admin-pass) shift
                tls_priv_key_admin_pass=$1
                ;;
            --tls-priv-key-node-pass) shift
                tls_priv_key_node_pass=$1
                ;;
            --tls-root-subject) shift
                tls_root_subject=$1
                ;;
            --tls-admin-subject) shift
                tls_admin_subject=$1
                ;;
            --tls-node-subject) shift
                tls_node_subject=$1
                ;;
            --tls-for-rest) shift
                tls_for_rest=$1
                ;;
            --)
                shift
                if [ $# -gt 0 ]; then
                    echo "ERROR: unexpected argument '$1'. Refer to the help menu." >&2
                    exit 1
                fi
                break
                ;;
        esac
        shift
    done
}


function set_legacy_defaults () {
    if [ -z "${cluster_name}" ]; then
        cluster_name="opensearch-cluster"
    fi

    if [ -z "${node_host}" ]; then
        node_host="[_local_, _site_]"
    fi

    if [ -z "${seed_hosts}" ]; then
        seed_hosts="[ \"127.0.0.1\", \"[::1]\" ]"  # ${node_name}]
    fi

    IFS=',' read -r -a roles <<< "${node_roles}"
    for role in "${roles[@]}"; do
        role=$(echo -e "${role}" | tr -d '[:space:]')
        if [ "${role}" == "cluster_manager" ]; then
            initial_cluster_manager_nodes="[ ${node_name} ]"
            break
        fi
    done

    if [ -n "${node_roles}" ]; then
        node_roles="[ ${node_roles} ]"
    fi

    if [ -z "${security_disabled}" ] || [ "${security_disabled}" != "yes" ]; then
        security_disabled="no"
    fi

    if [ -z "${tls_self_managed}" ] || [ "${tls_self_managed}" != "no" ]; then
        tls_self_managed="yes"
    fi

    if [ -z "${tls_init_setup}" ] || [ "${tls_init_setup}" != "yes" ]; then
        tls_init_setup="no"
    fi

    if [ -z "${tls_for_rest}" ] || [ "${tls_for_rest}" != "no" ]; then
        tls_for_rest="yes"
    fi
}


function validate_legacy_args () {
    err_message=""
    if [ -z "${node_name}" ]; then
        err_message="- '--node-name' is required \n"
    fi

    if [ "${tls_self_managed}" == "yes" ]; then
        if [ -z "${tls_priv_key_root_pass}" ]; then
            err_message="${err_message}- '--tls-priv-key-root-pass' is required \n"
        fi
    fi

    if [ -n "${err_message}" ]; then
        echo -e "The following errors occurred: \n${err_message}Refer to the help menu."
        exit 1
    fi
}


# Writes a value as the previous revisions did: a value in brackets is a
# list of comma separated entries, optionally double quoted.
function set_legacy_prop () {
    local target_file="${1}" key="${2}" value="${3}" item
    local -a items=()

    if [[ "${value}" != \[* ]]; then
        if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        set_yaml_prop "${target_file}" "${key}" "${value}"
        return
    fi

    value="${value#[}"
    value="${value%]}"
    IFS=',' read -r -a entries <<< "${value}"
    for item in "${entries[@]}"; do
        item=$(echo -e "${item}" | tr -d '[:space:]')
        if [[ "${item}" =~ ^\"(.*)\"$ ]]; then
            item="${BASH_REMATCH[1]}"
        fi
        [ -n "${item}" ] && items+=("${item}")
    done
    set_yaml_list "${target_file}" "${key}" "${items[@]}"
}


function setup_legacy () {
    source "${OPS_ROOT}"/helpers/snap-logger.sh "setup"
    source "${OPS_ROOT}"/helpers/set-conf.sh
    source "${OPS_ROOT}"/helpers/io.sh

    parse_legacy_args "$@"
    set_legacy_defaults
    validate_legacy_args

    local opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"
    set_legacy_prop "${opensearch_yaml}" "cluster.name" "${cluster_name}"
    set_legacy_prop "${opensearch_yaml}" "node.name" "${node_name}"
    if [ -n "${node_roles}" ]; then
        set_legacy_prop "${opensearch_yaml}" "node.roles" "${node_roles}"
    fi
    set_legacy_prop "${opensearch_yaml}" "network.host" "${node_host}"
    set_legacy_prop "${opensearch_yaml}" "discovery.seed_hosts" "${seed_hosts}"

    if [ -n "${initial_cluster_manager_nodes}" ]; then
        set_legacy_prop "${opensearch_yaml}" "cluster.initial_cluster_manager_nodes" "${initial_cluster_manager_nodes}"
    fi

    if [ "${security_disabled}" == "yes" ]; then
        set_yaml_prop "${opensearch_yaml}" "plugins.security.disabled" "true"
    else
        set_yaml_prop "${opensearch_yaml}" "plugins.security.disabled" "false"
    fi

    if [ "${tls_self_managed}" == "yes" ]; then
        local TLS_DIR="${OPS_ROOT}/security/tls"
        local key
        local -a keys

        if [ "${tls_init_setup}" == "yes" ]; then
            # create root and admin certs
            bash \
                "${TLS_DIR}"/self-managed-init.sh \
                    --root-password "${tls_priv_key_root_pass}" \
                    --admin-password "${tls_priv_key_admin_pass}" \
                    --root-subject "${tls_root_subject}" \
                    --admin-subject "${tls_admin_subject}" \
                    --rest-with-tls "${tls_for_rest}" \
                    --target-dir "${OPENSEARCH_PATH_CERTS}"

            keys=("root-ca" "root-ca-key" "admin" "admin-key")
            for key in "${keys[@]}"; do
                set_access_restrictions "${OPENSEARCH_PATH_CERTS}/${key}.pem" 660
            done
        fi

        # create node cert
        bash \
            "${TLS_DIR}"/self-managed-node.sh \
                --name "${node_name}" \
                --root-password "${tls_priv_key_root_pass}" \
                --node-password "${tls_priv_key_node_pass}" \
                --node-subject "${tls_node_subject}" \
                --rest-with-tls "${tls_for_rest}" \
                --target-dir "${OPENSEARCH_PATH_CERTS}"

        keys=("node-${node_name}" "node-${node_name}-key" "root-ca")
        for key in "${keys[@]}"; do
            set_access_restrictions "${OPENSEARCH_PATH_CERTS}/${key}.pem" 660
        done
        # serial number file of the root CA, created when signing
        set_access_restrictions "${OPENSEARCH_PATH_CERTS}/root-ca.srl" 660
    fi
}


detect_mode "$@"
case "${mode}" in
    legacy)   setup_legacy "$@" ;;
    settings) setup_settings "$@" ;;
esac

echo "Restart the daemon to apply: snap restart opensearch.daemon"
