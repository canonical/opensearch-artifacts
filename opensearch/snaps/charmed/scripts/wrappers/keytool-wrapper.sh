#!/bin/bash

set -e -o pipefail

exec "${JAVA_HOME}/bin/keytool" "$@"