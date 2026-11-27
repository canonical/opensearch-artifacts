#!/bin/bash

set -e

if [ -z "${OPENSEARCH_JAVA_OPTS}" ]; then
    OPENSEARCH_JAVA_OPTS="-Xms1g -Xmx1g"
fi

# The upstream agent expects its plugin home as the first positional argument.
# In this snap the plugin is below the writable distribution home.
if [ "${bin_script}" = opensearch-performance-analyzer/performance-analyzer-agent ] && [ "$#" -eq 0 ]; then
    set -- "${OPENSEARCH_PLUGINS}/opensearch-performance-analyzer"
fi

# bin_group: group to run the tool with, snap_daemon unless the app sets it
OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS}" "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid "${bin_group:-snap_daemon}" -- \
    ${OPENSEARCH_BIN}/${bin_script} "${@}"
