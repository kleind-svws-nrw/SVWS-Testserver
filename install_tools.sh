#!/bin/bash
##############################################################################
# Installiert die SVWS-Tools und bindet sie in den SVWS-Server ein (AppsPath)
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
Verwendung: bash $(basename "$0") [-v <Version>] [-d <Installationsverzeichnis>]

Lädt die SVWS-Tools der angegebenen Version von GitHub
(github.com/SVWS-NRW/SVWS-Tools/releases), entpackt sie unverändert in das
Installationsverzeichnis, trägt dieses als AppsPath in die svwsconfig.json
ein und startet den SVWS-Server neu. Vorhandene Dateien werden überschrieben.

Optionen:
  -v  Version der SVWS-Tools, z. B. 1.5.1
      (optional, Standard: neuestes Release von github.com/SVWS-NRW/SVWS-Tools)
  -d  Installationsverzeichnis der Tools (optional, Standard: /opt/app/svws/tools)
  -h  Diese Hilfe anzeigen (auch -help oder --help)

Beispiele:
  bash $(basename "$0")
  bash $(basename "$0") -v 1.5.1
  bash $(basename "$0") -v 1.5.1 -d /opt/app/svws/tools
EOF
    exit "${1:-1}"
}

# -h / -help / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "-help" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

TOOLSVERSION=""
TOOLS_DIR="/opt/app/svws/tools"

while getopts "v:d:" opt; do
    case $opt in
        v) TOOLSVERSION="${OPTARG#v}" ;;
        d) TOOLS_DIR="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$TOOLS_DIR" ] || [[ "$TOOLS_DIR" != /* ]]; then
    echo "Fehler: Das Installationsverzeichnis (-d) muss ein absoluter Pfad sein."
    usage
fi
TOOLS_DIR="${TOOLS_DIR%/}"


# svwsconfig.json suchen (Linux-Installer, ältere Installationen,
# install_svws_testserver_fromScratch.sh)
SVWS_CONFIG=""
for f in /opt/app/svws/svwsconfig.json /opt/app/svws/conf/svwsconfig.json /etc/app/svws/conf/svwsconfig.json \
         /opt/app/SVWS-Server/svws-server-app/svwsconfig.json; do
    if [ -f "$f" ]; then
        SVWS_CONFIG="$f"
        break
    fi
done
if [ -z "$SVWS_CONFIG" ]; then
    echo "Fehler: Keine svwsconfig.json gefunden. Ist der SVWS-Server installiert?"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Benötigte Programme installieren, falls sie fehlen
for tool in wget unzip jq; do
    command -v "$tool" &> /dev/null || { apt update && apt install -y "$tool"; }
done

# Ohne -v: neuestes Release der SVWS-Tools von GitHub ermitteln
if [ -z "$TOOLSVERSION" ]; then
    TOOLSVERSION=$(wget -qO- https://api.github.com/repos/SVWS-NRW/SVWS-Tools/releases/latest \
        | jq -r '.tag_name // empty')
    TOOLSVERSION="${TOOLSVERSION#v}"
    if [ -z "$TOOLSVERSION" ]; then
        echo "Fehler: Das neueste Release der SVWS-Tools konnte nicht ermittelt werden. Bitte mit -v angeben."
        exit 1
    fi
    echo "Neuestes Release der SVWS-Tools: ${TOOLSVERSION}"
fi
TOOLS_URL="https://github.com/SVWS-NRW/SVWS-Tools/releases/download/v${TOOLSVERSION}/svws-tools-${TOOLSVERSION}.zip"

#############################################
# 1. SVWS-Tools herunterladen und entpacken
#############################################
echo "Installiere SVWS-Tools ${TOOLSVERSION} nach ${TOOLS_DIR}..."
TMPZIP=$(mktemp --suffix=.zip)
if ! wget -q -O "$TMPZIP" "$TOOLS_URL"; then
    rm -f "$TMPZIP"
    echo "Fehler: SVWS-Tools ${TOOLSVERSION} konnten nicht geladen werden (gibt es dieses Release?)."
    exit 1
fi

# ZIP unverändert in das Installationsverzeichnis entpacken
mkdir -p "$TOOLS_DIR"
unzip -q -o "$TMPZIP" -d "$TOOLS_DIR"
rm -f "$TMPZIP"

# Besitzer wie das Verzeichnis der svwsconfig.json (Programmverzeichnis des SVWS-Servers)
chown -R --reference="$(dirname "$SVWS_CONFIG")" "$TOOLS_DIR"

#############################################
# 2. SVWS-Server auf die Tools hinweisen (AppsPath) und neu starten
#############################################
TMPJSON=$(mktemp)
if jq --arg p "$TOOLS_DIR" '.AppsPath = $p' "$SVWS_CONFIG" > "$TMPJSON"; then
    # cat statt mv: Besitzer und Rechte der svwsconfig.json bleiben erhalten
    cat "$TMPJSON" > "$SVWS_CONFIG"
    rm -f "$TMPJSON"
    echo "${SVWS_CONFIG}: \"AppsPath\" : \"${TOOLS_DIR}\""
else
    rm -f "$TMPJSON"
    echo "Fehler: ${SVWS_CONFIG} konnte nicht gelesen werden (kein gültiges JSON?)."
    exit 1
fi

systemctl restart svws

echo "------------------------------------------------"
echo "SVWS-Tools ${TOOLSVERSION} installiert in: ${TOOLS_DIR}"
echo "------------------------------------------------"
