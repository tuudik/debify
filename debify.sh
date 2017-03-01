#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

if [ ! -d /debs ]
then
    echo "Mount your Debian package directory to /debs."
    exit 1
fi

if [ ! -d /debs/incoming ] || [ ! "$(ls -A /debs/incoming/)" ]
then
    echo "ensure there are new packages in /debs/incoming."
    exit 1
fi

APTLY_REPO_OLD_NAME=debify
APTLY_REPO_NAME="repo-$APTLY_DISTRIBUTION"

if ! aptly repo show "$APTLY_REPO_NAME" >/dev/null 2>&1; then
    if aptly repo show "$APTLY_REPO_OLD_NAME" >/dev/null 2>&1; then
        echo "--- migrating repo name ---"
        aptly repo rename "$APTLY_REPO_OLD_NAME" "$APTLY_REPO_NAME"
    fi
fi

echo "--- creating repo: ---"
if ! aptly repo create \
    -component="$APTLY_COMPONENT" \
    -distribution="$APTLY_DISTRIBUTION" \
    "$APTLY_REPO_NAME" > out.log 2>&1; then

    if grep "already exists" out.log; then
        echo "repo already exists -- continuing"
    else
        cat out.log
        exit 1
    fi
fi

echo "--- adding packages: ---"
aptly repo add -force-replace=true -remove-files=true "$APTLY_REPO_NAME" /debs/incoming/

echo "---"
echo "current contents:"
aptly repo show $APTLY_REPO_NAME
echo "---"

if [ ! -z "$GPG_PASSPHRASE" ]
then
    passphrase="$GPG_PASSPHRASE"
elif [ ! -z "$GPG_PASSPHRASE_FILE" ]
then
    passphrase=$(<$GPG_PASSPHRASE_FILE)
fi

aptly publish repo \
    -architectures="$APTLY_ARCHITECTURES" \
    -passphrase="$passphrase" \
    -batch \
    -force-overwrite=true \
    $APTLY_REPO_NAME \
|| echo " --- updating instead... --- " && aptly publish update \
    -architectures="$APTLY_ARCHITECTURES" \
    -passphrase="$passphrase" \
    -batch \
    -force-overwrite=true \
    "$APTLY_DISTRIBUTION"

if [ ! -z "$KEYSERVER" ] && [ ! -z "$URI" ]
then
    release_sig_path=$(find /debs/public/dists -name Release.gpg | head -1)
    gpg_key_id=$(gpg --list-packets "$release_sig_path" | grep -oP "(?<=keyid ).+")

    if [[ "$URI" != */ ]]; then
        URI="${URI}/"
    fi

    cat > "/debs/public/install_${APTLY_DISTRIBUTION}" <<-END
#!/bin/sh -e
##
## How to install this repository:
##   curl -sSL ${URI}install_${APTLY_DISTRIBUTION} | sh
## OR
##   wget -qO- ${URI}install_${APTLY_DISTRIBUTION} | sh
##

END

    case "$URI" in
        https://*)
            cat >> "/debs/public/install_${APTLY_DISTRIBUTION}" <<-END
install_https() {
    if [ ! -e /usr/lib/apt/methods/https ]; then
        apt-get update && apt-get install -y apt-transport-https
    fi
}
install_https
END
    esac

    URL_STRIPPED=$(echo "$URI" | \
        sed 's#^\(http\|https\)##; s|[^A-Za-z0-9\.]|_|g; s#^_*##g; s#_*$##g')

    cat >> "/debs/public/install_${APTLY_DISTRIBUTION}" <<-END
do_install() {
    apt-key adv --keyserver $KEYSERVER --recv-keys $gpg_key_id
    echo "deb $URI $APTLY_DISTRIBUTION $APTLY_COMPONENT" >> /etc/apt/sources.list
    apt-get update
}
do_print() {
    echo "----------"
    echo "Done! Now you can install packages from the repository at $URI ."
    echo "Here is a list of all available packages:"
    grep Package /var/lib/apt/lists/${URL_STRIPPED}_dists_${APTLY_DISTRIBUTION}_*_Packages | sort | uniq
}

do_all() {
    do_install
    do_print
}
do_all
END
cp "/debs/public/install_${APTLY_DISTRIBUTION}" "/debs/install_${APTLY_DISTRIBUTION}"
fi
