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

set -e

OWNER="SVWS-NRW"
REPO="Schulungsunterlagen"
PATH_IN_REPO="Fachberatung_Anleitungen/Schulungsserver/Installationsskripte"

apt update && apt upgrade -y && apt autoremove -y
apt install curl jq -y

mkdir -p Installationsskripte
cd Installationsskripte

API_URL="https://api.github.com/repos/${OWNER}/${REPO}/contents/${PATH_IN_REPO}"

echo "Lade Dateiliste..."
curl -s "$API_URL" | jq -r '.[] | select(.type=="file") | .download_url' | while read -r url
do
    file=$(basename "$url")
    echo "Lade $file ..."
    curl -L -o "$file" "$url"
done

echo "Fertig."