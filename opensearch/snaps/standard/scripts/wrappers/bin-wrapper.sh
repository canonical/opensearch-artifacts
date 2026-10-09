#!/bin/bash

set -e


# Run with the root group: the config is owned by snap_daemon:root, and tools
# such as opensearch-plugin copy the parent's owner and group onto the files
# they create, which is only allowed to a member of that group.
OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS}" "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    ${OPENSEARCH_BIN}/${bin_script} "${@}"
