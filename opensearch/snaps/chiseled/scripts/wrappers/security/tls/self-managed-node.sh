#!/usr/bin/env bash

set -eu



source "${OPS_ROOT}"/helpers/snap-logger.sh "self-managed-node"
source "${OPS_ROOT}"/helpers/set-conf.sh
source "${OPS_ROOT}"/helpers/read-option-value.sh

usage() {
cat << EOF
usage: self-managed-node.sh --name name ...
To be ran / setup once per cluster.
--name            (Required)    Name of the node
--root-password   (Optional)    Passphrase of the root key when signing. If unset, the root key is expected unencrypted.
--node-password   (Optional)    Password for encrypting the node key. If unset, the key is generated unencrypted.
--node-subject    (Optional)    Subject for the node certificate
--sans            (Optional)    Subject alternative names of the node certificate, e.g: DNS:node1,IP:10.0.0.1
                                Defaults to localhost, the hostname, the FQDN and the IP addresses of this host
--rest-with-tls   (Optional)    Enum of either: yes (default), no. Enables the certificate for both the transport and rest layers or just the former
--target-dir      (Optional)    Where the certificates get stored
--help                          Shows help menu
EOF
}


# Args
name=""
root_password=""
node_password=""
node_subject=""
sans=""
rest_with_tls=""
target_dir=""


# Args handling
function parse_args () {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --name|--name=*)
                read_option_value "$@" || return 1
                name="$option_value"
                shift "$option_arguments"
                ;;
            --root-password|--root-password=*)
                read_option_value "$@" || return 1
                root_password="$option_value"
                shift "$option_arguments"
                ;;
            --node-password|--node-password=*)
                read_option_value "$@" || return 1
                node_password="$option_value"
                shift "$option_arguments"
                ;;
            --node-subject|--node-subject=*)
                read_option_value "$@" || return 1
                node_subject="$option_value"
                shift "$option_arguments"
                ;;
            --sans|--sans=*)
                read_option_value "$@" || return 1
                sans="$option_value"
                shift "$option_arguments"
                ;;
            --rest-with-tls|--rest-with-tls=*)
                read_option_value "$@" || return 1
                rest_with_tls="$option_value"
                shift "$option_arguments"
                ;;
            --target-dir|--target-dir=*)
                read_option_value "$@" || return 1
                target_dir="$option_value"
                shift "$option_arguments"
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done
}


function validate_args () {
    err_message=""
    if [ -z "${name}" ]; then
        err_message="- '--name' is required \n"
    fi

    if [ -n "${err_message}" ]; then
        echo -e "The following errors occurred: \n${err_message}Refer to the help menu."
        exit 1
    fi
}


# Lets other nodes verify this node by the name or address they reach it with
function default_sans () {
    local -a entries=("DNS:localhost" "IP:127.0.0.1" "IP:::1")
    local host_name
    for host_name in "$(hostname)" "$(hostname -f 2>/dev/null || true)"; do
        [ -n "${host_name}" ] && entries+=("DNS:${host_name}")
    done
    # peers may verify against the reverse DNS name of the address they dialed
    local ip
    local ip_name
    for ip in $(hostname -I 2>/dev/null || true); do
        entries+=("IP:${ip}")
        for ip_name in $(getent hosts "${ip}" 2>/dev/null | cut -d' ' -f2- || true); do
            entries+=("DNS:${ip_name}")
        done
    done

    # dedupe, preserving order
    local -A seen=()
    local -a unique=()
    local entry
    for entry in "${entries[@]}"; do
        [ -n "${seen["${entry}"]:-}" ] && continue
        seen["${entry}"]=1
        unique+=("${entry}")
    done

    local IFS=","
    echo "${unique[*]}"
}


parse_args "$@"
validate_args

if [ -z "${sans}" ]; then
    sans="$(default_sans)"
fi


# create the node cert
# Pass values with = so they are accepted even when they start with --.
source \
    "${OPS_ROOT}"/helpers/create-certificate.sh \
    --name="${name}" \
    --root-password="${root_password}" \
    --password="${node_password}" \
    --subject="${node_subject}" \
    --sans="${sans}" \
    --target-dir="${target_dir}" \
    --type=node


# set conf
opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"

set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemtrustedcas_filepath" "${target_dir}/root-ca.pem"
set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemcert_filepath" "${target_dir}/node-${name}.pem"
set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemkey_filepath" "${target_dir}/node-${name}-key.pem"
if [ -n "${node_password}" ]; then
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemkey_password" "${node_password}"
else
    # The new key is unencrypted; a password left by an earlier key prevents startup.
    remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemkey_password"
fi

if [ "${rest_with_tls}" == "yes" ]; then
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemtrustedcas_filepath" "${target_dir}/root-ca.pem"
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemcert_filepath" "${target_dir}/node-${name}.pem"
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_filepath" "${target_dir}/node-${name}-key.pem"
fi

# HTTP may already use this key even when --rest-with-tls is no. Keep its password
# in sync whenever its key file changes, but leave a separate HTTP key alone.
http_key_path=$(get_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_filepath")

# OpenSearch resolves relative paths from the configuration directory.
if [[ "${http_key_path}" != /* ]]; then
    http_key_path="${OPENSEARCH_PATH_CONF}/${http_key_path}"
fi

# Compare resolved paths so a relative path or symlink still identifies the same key.
if [ "$(readlink -m "${http_key_path}")" = "$(readlink -m "${target_dir}/node-${name}-key.pem")" ]; then
    if [ -n "${node_password}" ]; then
        set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_password" "${node_password}"
    else
        remove_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemkey_password"
    fi
fi

inverted_node_subject=$(
    openssl x509 \
        -subject \
        -nameopt RFC2253 \
        -noout \
        -in "${target_dir}/node-${name}.pem"
)
inverted_node_subject="${inverted_node_subject##subject=}"
# Add this node's DN if missing, keeping the other entries: they may belong
# to peer nodes, dropping them would break trust between nodes.
add_yaml_list_item "${opensearch_yaml}" "plugins.security.nodes_dn" "${inverted_node_subject}"
