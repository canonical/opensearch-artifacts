#!/usr/bin/env bash

set -eu


usage() {
cat << EOF
usage: create-certificate.sh --type root ...
To be ran / setup once per cluster.
--type            (Required)    Enum of either: root, admin, node, client
--password        (Optional)    Password for encrypting the key. If unset, the key is generated unencrypted.
--root-password   (Optional)    Passphrase of the root key when signing, defaults to --password
--name            (Optional)    Name of certificate: required for nodes and clients
--subject         (Optional)    Subject for the certificate, defaults to CN=localhost
--sans            (Optional)    Subject alternative names for nodes and clients, e.g: DNS:node1,IP:10.0.0.1
                                Defaults to DNS:<CN of the subject>
--target-dir      (Optional)    The target directory where the certificates and related resources are created
--help                          Shows help menu
EOF
}


# Defaults
ALLOWED_CERT_TYPES=("root" "admin" "node" "client") # "node" refers to the transport layer, whereas "client" refers to the "Rest" layer
KEY_SIZE_BITS=2048
LIFESPAN_DAYS=730
declare -A SUBJECTS=( ["root"]="/C=UK/ST=London/L=London/O=Canonical/OU=DataPlatform/CN=localhost"  # CN=root.dns.a-record
                      ["admin"]="/C=UK/ST=London/L=London/O=Canonical/OU=DataPlatform/CN=admin"
                      ["node"]="/C=UK/ST=London/L=London/O=Canonical/OU=DataPlatform/CN=localhost")  # CN=node1.dns.a-record


# Args
password=""
root_password=""
type=""
res_name=""
subject=""
sans=""
target_dir=""


# Args handling
function parse_args () {
    local LONG_OPTS_LIST=(
        "password"
        "root-password"
        "type"
        "name"
        "subject"
        "sans"
        "target-dir"
        "help"
    )
    local opts=$(getopt \
      --longoptions "$(printf "%s:," "${LONG_OPTS_LIST[@]}")" \
      --name "$(readlink -f "${BASH_SOURCE}")" \
      --options "" \
      -- "$@"
    )
    eval set -- "${opts}"

    while [ $# -gt 0 ]; do
        case $1 in
            --password) shift
                password=$1
                ;;
            --root-password) shift
                root_password=$1
                ;;
            --type) shift
                type=$1
                ;;
            --name) shift
                res_name=$1
                ;;
            --subject) shift
                subject=$1
                ;;
            --sans) shift
                sans=$1
                ;;
            --target-dir) shift
                target_dir=$1
                ;;
            --help) usage
                exit
                ;;
        esac
        shift
    done
}

function set_defaults () {
    if [ -z "${subject}" ] && [ "${type}" != "client" ]; then
        subject="${SUBJECTS["${type}"]}"
    fi

    if [ "${type}" == "node" ] || [ "${type}" == "client" ]; then
        res_name="${type}-${res_name}"
    else
        res_name="${type}"
    fi

    if [ -z "${target_dir}" ]; then
        target_dir="."
    fi

    if [ -z "${root_password}" ]; then
        root_password="${password}"
    fi
}

function validate_args () {
    err_message=""

    if ! echo "${ALLOWED_CERT_TYPES[*]}" | grep -wq "${type}"; then
        err_message="${err_message}- '--type' must be set to one of: ${ALLOWED_CERT_TYPES[*]}.\n"
    fi

    if [ -n "${res_name}" ] && [ "${res_name}" == "${type}." ]; then
        err_message="${err_message}- '--name' of the resource must be provided for nodes and clients (i.e: --name node1).\n"
    fi

    if [ -z "${subject}" ]; then
        err_message="${err_message}- '--subject' must be correctly set if specified, as it overrides the default value for local setups otherwise. \n"
    fi

    if [ -z "${target_dir}" ]; then
        err_message="${err_message}- '--target-dir' must be a correct path, or not set to point to the current directory. \n"
    fi

    if [ -n "${err_message}" ]; then
        echo -e "The following errors occurred: \n${err_message}Refer to the help menu."
        exit 1
    fi
}


# Certs creation
function create_root_certificate () {
    # generate a private key
    if [ -n "${password}" ]; then
        openssl genrsa \
            -out "${target_dir}/root-ca-key.pem" \
            -aes256 \
            -passout pass:"${password}" \
            ${KEY_SIZE_BITS}
    else
        openssl genrsa \
            -out "${target_dir}/root-ca-key.pem" \
            ${KEY_SIZE_BITS}
    fi

    # generate a root certificate
    local passin_args=()
    if [ -n "${password}" ]; then
        passin_args=(-passin pass:"${password}")
    fi
    openssl req \
        -new \
        -x509 \
        -sha256 \
        "${passin_args[@]}" \
        -key "${target_dir}/root-ca-key.pem" \
        -out "${target_dir}/root-ca.pem" \
        -subj "${subject}" \
        -days ${LIFESPAN_DAYS}
}


function create_certificate () {
    # generate a private key certificate
    if [ -n "${password}" ]; then
        openssl genrsa \
            -out "${target_dir}/${res_name}-key-temp.pem" \
            -aes256 \
            -passout pass:"${password}" \
            ${KEY_SIZE_BITS}
    else
        openssl genrsa \
            -out "${target_dir}/${res_name}-key-temp.pem" \
            ${KEY_SIZE_BITS}
    fi

    # convert created key to PKS-8 Java compatible format, encrypted
    # only when a password is provided
    local pkcs8_args=(
        "-inform" "PEM"
        "-outform" "PEM"
        "-in" "${target_dir}/${res_name}-key-temp.pem"
        "-topk8"
    )
    if [ -n "${password}" ]; then
        pkcs8_args+=(
            "-v1" "PBE-SHA1-3DES"
            "-passout" "pass:${password}"
            "-passin" "pass:${password}"
        )
    else
        pkcs8_args+=("-nocrypt")
    fi
    pkcs8_args+=("-out" "${target_dir}/${res_name}-key.pem")
    openssl pkcs8 "${pkcs8_args[@]}"

    # create a CSR
    local passin_args=()
    if [ -n "${password}" ]; then
        passin_args=(-passin pass:"${password}")
    fi
    openssl req \
        -new \
        "${passin_args[@]}" \
        -key "${target_dir}/${res_name}-key.pem" \
        -subj "${subject}" \
        -out "${target_dir}/${res_name}.csr"

    # generate the certificate
    gen_cert_args=(
        "x509"
        "-req"
        "-in" "${target_dir}/${res_name}.csr"
        "-CA" "${ca_dir}/root-ca.pem"
        "-CAkey" "${ca_dir}/root-ca-key.pem"
        # Keep serial-number updates in staging until the replacement is validated.
        "-CAserial" "${target_dir}/root-ca.srl"
        "-CAcreateserial"
        "-sha256"
        "-out" "${target_dir}/${res_name}.pem"
        "-days" "${LIFESPAN_DAYS}"
    )

    if [ -n "${root_password}" ]; then
        gen_cert_args+=("-passin" "pass:${root_password}")
    fi

    if [ "${type}" == "node" ] || [ "${type}" == "client" ]; then
        if [ -z "${sans}" ]; then
            CN="${subject##*'CN='}"
            sans="DNS:${CN}"
        fi
        echo "subjectAltName=${sans}" > "${target_dir}/${res_name}.ext"
        gen_cert_args+=(
            "-extfile" "${target_dir}/${res_name}.ext"
        )
    fi

    openssl "${gen_cert_args[@]}"

    # cleanup
    rm "${target_dir}/${res_name}-key-temp.pem"
    rm "${target_dir}/${res_name}.csr"
    rm -f "${target_dir}/${res_name}.ext"
}


# Generate and validate a complete replacement before changing the live files.
# The subshell keeps temporary paths and cleanup traps out of the calling wrapper.
function generate_and_publish_certificate () (
    [ -d "${target_dir}" ] || mkdir -p "${target_dir}"
    ca_dir=${target_dir}
    final_dir=${target_dir}

    if [[ "${type}" == root ]]; then
        pair_name=root-ca
    else
        pair_name=${res_name}
    fi

    files=("${pair_name}-key.pem" "${pair_name}.pem")
    if [[ "${type}" != root ]]; then
        files+=(root-ca.srl)
    fi

    target_dir=$(mktemp -d "${final_dir}/.certificate-XXXXXX")
    published=()
    cleanup() {
        local status=$?
        local file
        if (( status != 0 )); then
            # Restore any file replaced before a later rename failed.
            for file in "${published[@]}"; do
                if [[ -e "${target_dir}/old-${file}" ]]; then
                    if [[ ! "${target_dir}/old-${file}" -ef "${final_dir}/${file}" ]]; then
                        mv -f "${target_dir}/old-${file}" "${final_dir}/${file}"
                    fi
                else
                    rm -f "${final_dir}/${file}"
                fi
            done
        fi
        rm -rf "${target_dir}"
        exit "${status}"
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM

    # Keep the old files available without copying their contents.
    for file in "${files[@]}"; do
        if [[ -e "${final_dir}/${file}" || -L "${final_dir}/${file}" ]]; then
            [[ -f "${final_dir}/${file}" && ! -L "${final_dir}/${file}" ]] || exit 1
            ln "${final_dir}/${file}" "${target_dir}/old-${file}"
        fi
    done

    # Generate in staging; leaf certificates still use the existing CA.
    if [[ "${type}" == root ]]; then
        create_root_certificate
        verify_ca=${target_dir}/root-ca.pem
    else
        if [[ -f "${final_dir}/root-ca.srl" ]]; then
            cp "${final_dir}/root-ca.srl" "${target_dir}/root-ca.srl"
        fi
        create_certificate
        verify_ca=${ca_dir}/root-ca.pem
    fi

    # Check that the key matches and the CA validates the certificate.
    openssl pkey \
        -in "${target_dir}/${pair_name}-key.pem" \
        -passin "pass:${password}" \
        -pubout > "${target_dir}/key-public.pem"

    openssl x509 \
        -in "${target_dir}/${pair_name}.pem" \
        -pubkey -noout > "${target_dir}/cert-public.pem"

    cmp "${target_dir}/key-public.pem" "${target_dir}/cert-public.pem"
    openssl verify -CAfile "${verify_ca}" "${target_dir}/${pair_name}.pem"

    # Prepare metadata before changing any live file.
    for file in "${files[@]}"; do
        if [[ -e "${target_dir}/old-${file}" ]]; then
            chmod --reference="${target_dir}/old-${file}" "${target_dir}/${file}"
            chown --reference="${target_dir}/old-${file}" "${target_dir}/${file}"
        fi
    done

    # Each rename is atomic
    for file in "${files[@]}"; do
        published+=("${file}")
        mv -f "${target_dir}/${file}" "${final_dir}/${file}"
    done
)


parse_args "$@"
set_defaults
validate_args
generate_and_publish_certificate
