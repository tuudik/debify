#!/bin/bash
set -e
if [ ! -z "$GPG_PRIVATE_KEY" ]; then
    echo "$GPG_PRIVATE_KEY" > /tmp/priv.asc
    gpg --status-fd 2 --import /tmp/priv.asc 2> /tmp/gpg_output || :
    rm /tmp/priv.asc
    if ! grep IMPORT_OK /tmp/gpg_output; then
        cat gpg_output
        exit 1
    fi
fi

"$@"
