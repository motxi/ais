#! /usr/bin/env bash

# Bootstrap script for the installer.
#
# It downloads the repository, extracts the "scripts/" directory into "./ais"
# and makes "install.sh" executable. It does NOT start the installation, so you
# can review the files first.

set -euo pipefail

readonly REPO='motxi/ais'
readonly BRANCH='master'

readonly ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
readonly ARCHIVE="${BRANCH}.tar.gz"

readonly DESTINATION='ais'

echo "Downloading \"${REPO}\" (${BRANCH})..."

curl --location --fail --silent --show-error --output "${ARCHIVE}" "${ARCHIVE_URL}"

echo "Extracting the scripts to \"${DESTINATION}\"..."

# Start from a clean directory so no stale files from a previous run are left.
rm --recursive --force "${DESTINATION}"
mkdir --parents "${DESTINATION}"

# The archive contains a top-level "<repo>-<branch>" directory. Only the
# "scripts/" directory is extracted, and both leading directories are stripped
# so the scripts end up directly in "${DESTINATION}".
tar \
    --extract \
    --gzip \
    --file "${ARCHIVE}" \
    --directory "${DESTINATION}" \
    --strip-components 2 \
    --wildcards '*/scripts/*'

rm --force "${ARCHIVE}"

[[ -f "${DESTINATION}/install.sh" ]] || {
    echo "Missing \"install.sh\" in the \"scripts/\" directory of \"${REPO}\" (${BRANCH})." >&2
    exit 1
}

chmod +x "${DESTINATION}/install.sh"

echo 'Done!'
echo "Run \"./${DESTINATION}/install.sh\" to start the installation."
echo "You should manually review the files inside \"${DESTINATION}\" first."
