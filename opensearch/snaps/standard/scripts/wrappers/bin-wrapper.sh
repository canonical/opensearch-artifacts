#!/bin/bash

set -e

if [ -z "${OPENSEARCH_JAVA_OPTS}" ]; then
    OPENSEARCH_JAVA_OPTS="-Xms1g -Xmx1g"
fi

group="snap_daemon"
if [ "${bin_script}" = "opensearch-plugin" ]; then
    group="root"
fi

OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS}" "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid "${group}" -- \
    ${OPENSEARCH_BIN}/${bin_script} "${@}"
