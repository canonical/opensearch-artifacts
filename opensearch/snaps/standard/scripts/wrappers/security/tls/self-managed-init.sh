#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/snap-logger.sh "self-managed-init"
source "${OPS_ROOT}"/helpers/set-conf.sh
source "${OPS_ROOT}"/helpers/read-option-value.sh


usage() {
cat << EOF
usage: self-managed-init.sh --target-dir dir ...
To be ran / setup once per cluster.
--root-password   (Optional)    Password for encrypting the root key. If unset, the keys are generated unencrypted.
--admin-password  (Optional)    Password for encrypting the admin key. If unset, the key is generated unencrypted.
--root-subject    (Optional)    Subject for the root certificate, defaults to [..../CN=localhost]
--admin-subject   (Optional)    Subject for the admin certificate
--rest-with-tls   (Optional)    Enum of either: yes (default), no. Enables the certificate for both the transport and rest layers or just the former
--target-dir      (Optional)    Where the certificates get stored
--help                          Shows help menu
EOF
}


# Args
root_password=""
admin_password=""
root_subject=""
admin_subject=""
rest_with_tls=""
target_dir=""


# Args handling
function parse_args () {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --root-password|--root-password=*)
                read_option_value "$@" || return 1
                root_password="$option_value"
                shift "$option_arguments"
                ;;
            --admin-password|--admin-password=*)
                read_option_value "$@" || return 1
                admin_password="$option_value"
                shift "$option_arguments"
                ;;
            --root-subject|--root-subject=*)
                read_option_value "$@" || return 1
                root_subject="$option_value"
                shift "$option_arguments"
                ;;
            --admin-subject|--admin-subject=*)
                read_option_value "$@" || return 1
                admin_subject="$option_value"
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


parse_args "$@"


# create the root cert
# Pass values with = so they are accepted even when they start with --.
source \
    "${OPS_ROOT}"/helpers/create-certificate.sh \
    --password="${root_password}" \
    --subject="${root_subject}" \
    --target-dir="${target_dir}" \
    --type=root

# create the admin cert
source \
    "${OPS_ROOT}"/helpers/create-certificate.sh \
    --root-password="${root_password}" \
    --password="${admin_password}" \
    --subject="${admin_subject}" \
    --target-dir="${target_dir}" \
    --type=admin


# set conf
opensearch_yaml="${OPENSEARCH_PATH_CONF}/opensearch.yml"

set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.pemtrustedcas_filepath" "${target_dir}/root-ca.pem"
set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.transport.enforce_hostname_verification" "true"

if [ "${rest_with_tls}" == "yes" ]; then
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.pemtrustedcas_filepath" "${target_dir}/root-ca.pem"
    set_yaml_prop "${opensearch_yaml}" "plugins.security.ssl.http.enabled" "true"
fi


inverted_admin_subject=$(
    openssl x509 \
        -subject \
        -nameopt RFC2253 \
        -noout \
        -in "${target_dir}/admin.pem"
)
inverted_admin_subject="${inverted_admin_subject##subject=}"
set_yaml_list "${opensearch_yaml}" "plugins.security.authcz.admin_dn" "${inverted_admin_subject}"
