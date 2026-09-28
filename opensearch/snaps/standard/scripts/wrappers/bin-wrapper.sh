#!/bin/bash

set -e

if [ -z "${OPENSEARCH_JAVA_OPTS}" ]; then
    OPENSEARCH_JAVA_OPTS="-Xms1g -Xmx1g"
fi

# Run with the root group: the config is owned by snap_daemon:root, and tools
# such as opensearch-plugin copy the parent's owner and group onto the files
# they create, which is only allowed to a member of that group.
OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS}" "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    ${OPENSEARCH_BIN}/${bin_script} "${@}"
