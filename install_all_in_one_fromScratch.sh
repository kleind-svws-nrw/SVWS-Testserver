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
Verwendung: bash $(basename "$0") [-m <ServerMode>] [-b <Branch>] [-p <Passwort>]

Installiert einen All-in-one-Testserver. Der SVWS-Server wird dabei
aus einem GitHub-Branch gebaut.

Optionen:
  -m  ServerMode, z. B. dev, alpha, beta, stable (optional, Standard: dev)
  -b  Git-Branch, z. B. dev oder master (optional, Standard: dev)
  -p  Passwort für den MariaDB-Root-User (optional, sonst Zufallsgenerierung)
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
MYSQLROOTPW=""

# Parameter mit getopts einlesen
while getopts "p:b:m:" opt; do
  case $opt in
    p) MYSQLROOTPW="$OPTARG" ;;
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
if [ -z "$MYSQLROOTPW" ]; then
    MYSQLROOTPW=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    PW_WAS_GENERATED=true
else
    PW_WAS_GENERATED=false
fi

# Arbeitsverzeichnis: Ordner, in dem dieses Skript liegt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_SCRIPT_URL="https://github.com/kleind-svws-nrw/SVWS-Testserver/raw/refs/heads/main/download_all_scripts.sh"
SCRIPTS_DIR="${SCRIPT_DIR}/Installationsskripte"

#############################################
# 1. Alle Installationsskripte herunterladen
#############################################
cd "$SCRIPT_DIR"

# wget installieren, falls nicht vorhanden
if ! command -v wget &> /dev/null; then
    apt update && apt install -y wget
fi

# In eine temporäre Datei laden, damit eine vorhandene download_all_scripts.sh
# im Skriptordner (z. B. im Git-Repository) nicht überschrieben wird
DOWNLOAD_SCRIPT=$(mktemp --suffix=.sh)

echo "Lade download_all_scripts.sh herunter..."
if ! wget -q -O "$DOWNLOAD_SCRIPT" "$DOWNLOAD_SCRIPT_URL"; then
    rm -f "$DOWNLOAD_SCRIPT"
    echo "Fehler: download_all_scripts.sh konnte nicht von $DOWNLOAD_SCRIPT_URL geladen werden."
    exit 1
fi

# Skript ausführen: lädt alle Skripte nach ./Installationsskripte
if ! bash "$DOWNLOAD_SCRIPT"; then
    rm -f "$DOWNLOAD_SCRIPT"
    echo "Fehler: download_all_scripts.sh wurde mit einem Fehler beendet."
    exit 1
fi
rm -f "$DOWNLOAD_SCRIPT"

echo "Die Installationsskripte liegen in: $SCRIPTS_DIR"

#############################################
# TODO: weitere Installationsschritte
#############################################


#############################################
# Abschluss
#############################################
echo "------------------------------------------------"
echo "Installation abgeschlossen."
if [ "$PW_WAS_GENERATED" = true ]; then
    echo "WICHTIG: Das generierte MariaDB-Root-Passwort lautet: $MYSQLROOTPW"
fi
echo "------------------------------------------------"

#############################################
# Dieses Skript in das Skriptverzeichnis verschieben
#############################################
SELF="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

if [ -d "${SCRIPT_DIR}/.git" ]; then
    # Schutz: im Git-Repository nicht verschieben, sonst fehlt die Datei dort
    echo "Hinweis: $(basename "$SELF") liegt in einem Git-Repository und wird nicht verschoben."
elif [ "$SCRIPT_DIR" != "$SCRIPTS_DIR" ] && [ -d "$SCRIPTS_DIR" ]; then
    mv -f "$SELF" "${SCRIPTS_DIR}/"
    echo "$(basename "$SELF") wurde nach $SCRIPTS_DIR verschoben."
fi
