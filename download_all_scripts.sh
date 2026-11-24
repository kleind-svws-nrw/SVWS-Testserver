#!/bin/bash
##############################################################################
# Lädt alle Installationsskripte dieser Sammlung herunter
##############################################################################
#
# Copyright (c) November 2026 Theo Richter & David Klein
#
# SPDX-License-Identifier: MIT
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
##############################################################################

# --- Hilfe ---
usage() {
    cat <<EOF
Verwendung: bash $(basename "$0")

Lädt alle Skripte aus github.com/kleind-svws-nrw/SVWS-Testserver (Branch main)
in den Unterordner ./Installationsskripte herunter.
Vorher werden das System aktualisiert und curl sowie jq installiert.

Optionen:
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0")
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

set -e

OWNER="kleind-svws-nrw"
REPO="SVWS-Testserver"
PATH_IN_REPO=""        # leer = Hauptverzeichnis des Repositorys
BRANCH="main"          # nur stabile Stände

apt update && apt upgrade -y && apt autoremove -y
apt install curl jq -y

mkdir -p Installationsskripte
cd Installationsskripte

API_URL="https://api.github.com/repos/${OWNER}/${REPO}/contents"
[ -n "$PATH_IN_REPO" ] && API_URL="${API_URL}/${PATH_IN_REPO}"
API_URL="${API_URL}?ref=${BRANCH}"

echo "Lade Dateiliste..."
curl -s "$API_URL" | jq -r '.[] | select(.type=="file") | .download_url' | while read -r url
do
    file=$(basename "$url")
    echo "Lade $file ..."
    curl -L -o "$file" "$url"
done

echo "Fertig."