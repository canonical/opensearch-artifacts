#!/usr/bin/env bash

# Reads the value of the option in $1, given as --option=value or --option value.
# Sets option_value, and option_arguments to the number of arguments to shift.
read_option_value() {
    option_arguments=1
    option_value=""

    if [[ "$1" == *=* ]]; then
        # Everything after the first '=' is an explicit value, including empty text.
        option_value="${1#*=}"
        return 0
    fi

    if [ "$#" -lt 2 ]; then
        echo "Missing value for option '$1'." >&2
        return 1
    fi

    if [[ "$2" == --* ]]; then
        echo "Missing value for option '$1'. Use $1=<value> for values starting with --." >&2
        return 1
    fi

    option_value="$2"
    option_arguments=2
}
