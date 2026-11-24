#!/bin/bash
##############################################################################
# Aktualisiert die WebLuPO (überschreibt eine vorhandene Installation)
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
Verwendung: bash $(basename "$0") -v <Version>

Lädt die WebLuPO der angegebenen Version von GitHub herunter und entpackt sie
nach /var/www/html/weblupo. Eine vorhandene Installation wird ohne Rückfrage
überschrieben. Die nginx-Konfiguration bleibt unverändert.

Optionen:
  -v  Version des SVWS-Servers, z. B. 1.5.1 (Pflicht)
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -v 1.5.1
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

INSTALLPATH=/var/www/html/weblupo
SVWSVERSION=""

# Parameter auswerten
while getopts "v:" opt; do
    case "$opt" in
        v) SVWSVERSION="${OPTARG#v}" ;;
        *) usage ;;
    esac
done

# Verpflichtende Prüfung der SVWS-Version
if [ -z "$SVWSVERSION" ]; then
    echo -e "\e[31mFehler: Die SVWS-Version (-v) muss angegeben werden!\e[0m"
    usage
fi

DOWNLOADPATH="https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/SVWS-Laufbahnplanung-${SVWSVERSION}.zip"

echo "Aktualisiere WebLuPO auf Version $SVWSVERSION in $INSTALLPATH..."

# wget und unzip installieren, falls nicht vorhanden
for tool in wget unzip; do
    command -v "$tool" &> /dev/null || { apt update && apt install -y "$tool"; }
done

# Erst herunterladen, dann die alte Installation ersetzen.
# So bleibt die bisherige WebLuPO erhalten, falls der Download fehlschlägt.
TMPZIP=$(mktemp --suffix=.zip)
echo "Download von $DOWNLOADPATH"
if ! wget -q -O "$TMPZIP" "$DOWNLOADPATH"; then
    rm -f "$TMPZIP"
    echo "Fehler: Download fehlgeschlagen. Gibt es die Version $SVWSVERSION?"
    echo "Die bisherige Installation wurde nicht verändert."
    exit 1
fi

# Vorhandene Installation überschreiben
mkdir -p "$INSTALLPATH"
rm -rf "${INSTALLPATH:?}"/*
unzip -q -o "$TMPZIP" -d "$INSTALLPATH"
rm -f "$TMPZIP"

# Berechtigungen setzen
chown -R www-data:www-data "$INSTALLPATH"
find "$INSTALLPATH" -type d -exec chmod 755 {} +
find "$INSTALLPATH" -type f -exec chmod 644 {} +

SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "\n################# WebLuPO $SVWSVERSION aktualisiert! ####################\n"
echo "Die WebLuPO ist erreichbar unter: ${SERVER_IP}"
