#!/bin/bash
##############################################################################
# Installiert einen All-in-one-Testserver auf Basis eines GitHub-Branches
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
Verwendung: bash $(basename "$0") [-m <ServerMode>] [-b <Branch>] [-p <Passwort>] [-v <Version>]

Installiert einen All-in-one-Testserver. Der SVWS-Server wird dabei
aus einem GitHub-Branch gebaut.

Optionen:
  -m  ServerMode, z. B. dev, alpha, beta, stable (optional, Standard: dev)
  -b  Git-Branch, z. B. dev oder master (optional, Standard: dev)
  -p  Passwort für den MariaDB-Root-User (optional, sonst Zufallsgenerierung)
  -v  Release-Version für WeNoM, WebLuPO und SVWS-Tools, z. B. 1.5.1
      (optional, Standard: neueste Version von github.com/SVWS-NRW/SVWS-Server/releases)
  -h  Diese Hilfe anzeigen (auch -help oder --help)

Beispiel:
  bash $(basename "$0") -p svwsadmin
EOF
    exit "${1:-1}"
}

# -h / -help / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "-help" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

# Standardwerte
BRANCH="dev"
SERVERMODE="dev"
MARIADB_ROOT_PASSWORD=""
SVWSVERSION=""

# Parameter mit getopts einlesen
while getopts "p:b:m:v:" opt; do
  case $opt in
    v) SVWSVERSION="${OPTARG#v}" ;;
    p) MARIADB_ROOT_PASSWORD="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    m) SERVERMODE="$OPTARG" ;;
    *) usage ;;
  esac
done

# Fallback, falls -b oder -m mit leerem Wert übergeben wurden
[ -z "$BRANCH" ] && BRANCH="dev"
[ -z "$SERVERMODE" ] && SERVERMODE="dev"
echo "Verwende Branch: $BRANCH, ServerMode: $SERVERMODE"

# Passwort generieren, falls nicht angegeben
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    MARIADB_ROOT_PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    PW_WAS_GENERATED=true
else
    PW_WAS_GENERATED=false
fi

#############################################
# Release-Version für WeNoM, WebLuPO und SVWS-Tools ermitteln
# (vor der Installation, damit ein Fehler sofort auffällt)
#############################################
# Aus einem Branch gebaute Server haben keine Release-Downloads,
# daher werden WeNoM, WebLuPO und SVWS-Tools aus einem veröffentlichten Release geladen.
if [ -z "$SVWSVERSION" ]; then
    for tool in curl jq; do
        command -v "$tool" &> /dev/null || { apt update && apt install -y "$tool"; }
    done
    SVWSVERSION=$(curl -s https://api.github.com/repos/SVWS-NRW/SVWS-Server/releases/latest | jq -r '.tag_name // empty')
    SVWSVERSION="${SVWSVERSION#v}"
    if [ -z "$SVWSVERSION" ]; then
        echo "Fehler: Die neueste Release-Version konnte nicht ermittelt werden. Bitte mit -v angeben."
        exit 1
    fi
fi
echo "Verwende Release-Version für WeNoM, WebLuPO und SVWS-Tools: $SVWSVERSION"

# Ordner, in dem dieses Skript liegt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_SCRIPT_URL="https://github.com/kleind-svws-nrw/SVWS-Testserver/raw/refs/heads/main/download_all_scripts.sh"

# Skripte, die für die All-in-one-Installation benötigt werden
REQUIRED_SCRIPTS=(
    install_svws_testserver_fromScratch.sh
    install_wenom_testserver.sh
    install_weblupo_testserver.sh
    create_svws_testdbs.sh
    delete_all_svws_dbs.sh
    generate_svws_userpasswords.sh
)

#############################################
# 1. Installationsskripte bereitstellen
#############################################
# Liegen alle benötigten Skripte neben diesem Skript (Skriptordner oder
# Git-Repository), werden sie direkt verwendet. Nur wenn etwas fehlt,
# werden alle Skripte einmalig über download_all_scripts.sh geladen.

MISSING_SCRIPTS=()
for s in "${REQUIRED_SCRIPTS[@]}"; do
    [ -f "${SCRIPT_DIR}/${s}" ] || MISSING_SCRIPTS+=("$s")
done

if [ ${#MISSING_SCRIPTS[@]} -eq 0 ]; then
    SCRIPTS_DIR="$SCRIPT_DIR"
    echo "Alle benötigten Skripte gefunden, verwende: $SCRIPTS_DIR"
else
    echo "Fehlende Skripte: ${MISSING_SCRIPTS[*]}"
    echo "Lade alle Installationsskripte herunter..."
    cd "$SCRIPT_DIR"

    # wget installieren, falls nicht vorhanden
    if ! command -v wget &> /dev/null; then
        apt update && apt install -y wget
    fi

    # In eine temporäre Datei laden und von dort ausführen
    DOWNLOAD_SCRIPT=$(mktemp --suffix=.sh)
    if ! wget -q -O "$DOWNLOAD_SCRIPT" "$DOWNLOAD_SCRIPT_URL"; then
        rm -f "$DOWNLOAD_SCRIPT"
        echo "Fehler: download_all_scripts.sh konnte nicht von $DOWNLOAD_SCRIPT_URL geladen werden."
        exit 1
    fi

    # lädt alle Skripte nach ./Installationsskripte
    if ! bash "$DOWNLOAD_SCRIPT"; then
        rm -f "$DOWNLOAD_SCRIPT"
        echo "Fehler: download_all_scripts.sh wurde mit einem Fehler beendet."
        exit 1
    fi
    rm -f "$DOWNLOAD_SCRIPT"

    SCRIPTS_DIR="${SCRIPT_DIR}/Installationsskripte"

    # Prüfen, ob jetzt alles da ist
    for s in "${REQUIRED_SCRIPTS[@]}"; do
        if [ ! -f "${SCRIPTS_DIR}/${s}" ]; then
            echo "Fehler: $s fehlt auch nach dem Download in $SCRIPTS_DIR."
            exit 1
        fi
    done
    echo "Die Installationsskripte liegen in: $SCRIPTS_DIR"
fi

#############################################
# 2. SVWS-Server aus dem GitHub-Branch bauen und installieren
#############################################
echo "Starte install_svws_testserver_fromScratch.sh (Branch: $BRANCH, ServerMode: $SERVERMODE)..."
if ! bash "${SCRIPTS_DIR}/install_svws_testserver_fromScratch.sh" \
        -b "$BRANCH" \
        -m "$SERVERMODE" \
        -p "$MARIADB_ROOT_PASSWORD"; then
    echo "Fehler: install_svws_testserver_fromScratch.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 3. WeNoM installieren (Apache2, nur Port 443)
# Vor der WebLuPO, damit Port 80 bei der Apache-Installation noch frei ist
#############################################
echo "Starte install_wenom_testserver.sh (Version: $SVWSVERSION)..."
if ! bash "${SCRIPTS_DIR}/install_wenom_testserver.sh" -v "$SVWSVERSION"; then
    echo "Fehler: install_wenom_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 4. WebLuPO installieren (nginx, Port 80)
#############################################
echo "Starte install_weblupo_testserver.sh (Version: $SVWSVERSION)..."
if ! bash "${SCRIPTS_DIR}/install_weblupo_testserver.sh" -v "$SVWSVERSION"; then
    echo "Fehler: install_weblupo_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 5. SVWS-Tools installieren
#############################################
TOOLS_DIR="/opt/app/svws/tools"
TOOLS_URL="https://github.com/SVWS-NRW/SVWS-Tools/releases/download/v${SVWSVERSION}/svws-tools-${SVWSVERSION}.zip"
SVWS_CONFIG="/opt/app/SVWS-Server/svws-server-app/svwsconfig.json"

echo "Installiere SVWS-Tools ${SVWSVERSION} nach ${TOOLS_DIR}..."
TMPZIP=$(mktemp --suffix=.zip)
if ! wget -q -O "$TMPZIP" "$TOOLS_URL"; then
    rm -f "$TMPZIP"
    echo "Fehler: SVWS-Tools ${SVWSVERSION} konnten nicht geladen werden (gibt es dieses Release?)."
    exit 1
fi

# ZIP unverändert in den Tools-Ordner entpacken (vorhandene Dateien werden überschrieben)
mkdir -p "$TOOLS_DIR"
unzip -q -o "$TMPZIP" -d "$TOOLS_DIR"
rm -f "$TMPZIP"
chown -R svws:svws "$TOOLS_DIR"

# SVWS-Server auf die Tools hinweisen (AppsPath) und neu starten
sed -i 's|"AppsPath"[[:space:]]*:[[:space:]]*[^,]*|"AppsPath" : "'"$TOOLS_DIR"'"|' "$SVWS_CONFIG"
systemctl restart svws

#############################################
# TODO: weitere Installationsschritte
#############################################


#############################################
# Abschluss
#############################################
echo "------------------------------------------------"
echo "Installation abgeschlossen."
if [ "$PW_WAS_GENERATED" = true ]; then
    echo "WICHTIG: Das generierte MariaDB-Root-Passwort lautet: $MARIADB_ROOT_PASSWORD"
fi
echo "------------------------------------------------"

