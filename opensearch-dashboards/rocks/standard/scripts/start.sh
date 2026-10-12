#!/usr/bin/env bash

# No xtrace: it would print the passwords and the secret settings
set -eu

# The settings that can be given as a variable, named as in the upstream
# image, e.g. OPENSEARCH_HOSTS for opensearch.hosts. The other settings are
# set in opensearch_dashboards.yml.
opensearch_dashboards_vars=(
    opensearch.hosts
    opensearch.username
    opensearch.password
    opensearch.ssl.verificationMode
    opensearch.ssl.certificateAuthorities
    server.host
    server.port
    server.ssl.enabled
    server.ssl.certificate
    server.ssl.key
)

# Settings passed to OpenSearch Dashboards as options, which take precedence
# over opensearch_dashboards.yml: the file is never modified, so it can be
# mounted read-only
longopts=()
overridden=()

for setting in "${opensearch_dashboards_vars[@]}"; do
    # opensearch.hosts -> OPENSEARCH_HOSTS
    env_var="${setting^^}"
    env_var="${env_var//./_}"

    value="${!env_var:-}"
    if [ -n "${value}" ]; then
        longopts+=("--${setting}=${value}")
        overridden+=("${setting}")
    fi
done

# Upstream removes the plugin and its settings from opensearch_dashboards.yml.
# Disabling it has the same effect, without changing the files of the rock.
if [ "${DISABLE_SECURITY_DASHBOARDS_PLUGIN:-}" = "true" ]; then
    echo "Disabling OpenSearch Security Dashboards Plugin"
    longopts+=("--opensearch_security.enabled=false")
fi

# The names only, the values may be secrets
if [ "${#overridden[@]}" -gt 0 ]; then
    echo "Settings overridden: ${overridden[*]}"
fi

# Like upstream, read the statistics of the container from the root of the
# cgroup filesystem, where Docker mounts them, instead of the cgroup paths
# of /proc/self/cgroup.
exec "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards \
    --ops.cGroupOverrides.cpuPath=/ \
    --ops.cGroupOverrides.cpuAcctPath=/ \
    "${longopts[@]}"
