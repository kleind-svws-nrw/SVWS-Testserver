#!/bin/bash
##############################################################################
# Importiert SQLite-Testdatenbanken in den SVWS-Server
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
Verwendung: bash $(basename "$0") [-u <Benutzer>] [-p <Passwort>] [-d <URL>]

Importiert SQLite-Testdatenbanken in den SVWS-Server (https://localhost:8443).
Ohne -d werden alle .sqlite-Dateien aus github.com/SVWS-NRW/SVWS-TestSqlites importiert.
Das MariaDB-Root-Passwort wird aus der .env neben dem Skript gelesen.

Optionen:
  -u  Benutzername für die neuen Schemata (Standard: svwsadmin)
  -p  Passwort dieses Benutzers (Standard: svwsadmin)
  -d  URL einer einzelnen .sqlite-Datei
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -u svwsadmin -p geheim
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

# Abbrechen, wenn ein Befehl mit Fehler beendet wird
set -e

# Speicherort des Skripts ermitteln
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

MYSQLROOTPW=""

# MariaDB-Root-Passwort aus der .env Datei lesen
if [ ! -f "$ENV_FILE" ]; then
    echo "Fehler: Die Datei '$ENV_FILE' wurde nicht gefunden!"
    echo "Sie muss die Zeile 'MARIADB_ROOT_PASSWORD=<Passwort>' enthalten."
    exit 1
fi

ENV_PASS=$(grep -E '^MARIADB_ROOT_PASSWORD=' "$ENV_FILE" | cut -d '=' -f2- | tr -d '"' | tr -d "'")
if [ -n "$ENV_PASS" ]; then
    MYSQLROOTPW="$ENV_PASS"
    echo "✓ Passwort aus .env geladen."
else
    echo "Fehler: Kein Passwort gefunden!"
    echo "Es wurde kein 'MARIADB_ROOT_PASSWORD' in '$ENV_FILE' gefunden."
    exit 1
fi

# --- STANDARD-EINSTELLUNGEN ---
REPO_URL="https://github.com/SVWS-NRW/SVWS-TestSqlites"
FOLDER_NAME="SVWS-TestSqlites"
USERNAME="svwsadmin"
PASSWORD="svwsadmin"
API_URL="https://localhost:8443/api/schema/root/import/sqlite/"
DOWNLOAD_URL=""

# --- PARAMETER VERARBEITUNG (getopts) ---
while getopts "u:p:d:" opt; do
  case $opt in
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    d) DOWNLOAD_URL="$OPTARG" ;;
    *) usage ;;
  esac
done

echo "Schema-Benutzer: $USERNAME"

# Ordner erstellen, falls er nicht existiert
mkdir -p "$FOLDER_NAME"

# --- ZWEI PFADE: Einzel-Download ODER Git-Repo ---
if [ -n "$DOWNLOAD_URL" ]; then
    echo -e "\n=== Einzelne Datei herunterladen ==="
    echo "URL: $DOWNLOAD_URL"
    
    # Dateinamen aus der URL extrahieren
    FILE_NAME=$(basename "$DOWNLOAD_URL")
    
    # Prüfe ob curl oder wget vorhanden ist
    if command -v curl &> /dev/null; then
        curl -sL "$DOWNLOAD_URL" -o "${FOLDER_NAME}/${FILE_NAME}"
    elif command -v wget &> /dev/null; then
        wget -q "$DOWNLOAD_URL" -O "${FOLDER_NAME}/${FILE_NAME}"
    else
        echo "Fehler: Weder curl noch wget ist installiert, um die Datei herunterzuladen."
        exit 1
    fi
    echo "✓ Datei '$FILE_NAME' wurde nach '$FOLDER_NAME/' heruntergeladen."

else
    echo -e "\n=== 1. Prüfe Git-Installation ==="
    if ! command -v git &> /dev/null; then
        echo "Git ist nicht installiert. Versuche Git zu installieren..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y git
        elif command -v yum &> /dev/null; then
            sudo yum install -y git
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm git
        else
            echo "Fehler: Paketmanager nicht erkannt. Bitte installiere Git manuell."
            exit 1
        fi
    else
        echo "✓ Git ist bereits installiert."
    fi

    echo -e "\n=== 2. Prüfe Verzeichnis und Repository ==="
    if [ ! -d "$FOLDER_NAME/.git" ]; then
        echo "Ordner '$FOLDER_NAME' ist kein Git-Repo. Klonen wird gestartet..."
        git clone "$REPO_URL" "$FOLDER_NAME"
    else
        echo "✓ Ordner '$FOLDER_NAME' existiert bereits."
    fi

    echo -e "\n=== 3. Wechsel in das Verzeichnis und git pull ==="
    cd "$FOLDER_NAME"
    echo "Aktualisiere Repository..."
    git pull
    # Wieder ins Ursprungsverzeichnis wechseln
    cd "$SCRIPT_DIR"
fi


echo -e "\n=== 4. Suche nach .sqlite Dateien im Ordner '$FOLDER_NAME' ==="
shopt -s nullglob
sqlite_files=("${FOLDER_NAME}"/*.sqlite)

if [ ${#sqlite_files[@]} -eq 0 ]; then
    echo "Keine .sqlite-Dateien im Ordner '$FOLDER_NAME' gefunden."
    exit 0
fi

echo "Gefundene Dateien: ${#sqlite_files[@]}"


echo -e "\n=== 5. Führe Import via Curl für jede Datei aus ==="
for file in "${sqlite_files[@]}"; do
    # Dateinamen isolieren und Endung abschneiden für den Schema-Namen
    file_name=$(basename "$file")
    SCHEMA_NAME="${file_name%.sqlite}"

    echo "----------------------------------------"
    echo "Verarbeite Datei: $file"
    echo "Ziel-Schema:      $SCHEMA_NAME"
    
    curl -k -X POST "${API_URL}${SCHEMA_NAME}" \
      -u "root:${MYSQLROOTPW}" \
      -H 'accept: application/json' \
      -H 'Content-Type: multipart/form-data' \
      -F "database=@${file}" \
      -F "schemaUsername=${USERNAME}" \
      -F "schemaUserPassword=${PASSWORD}"

    echo -e "\n"
done

echo "=== Fertig! ==="