#!/bin/bash
##############################################################################
# Installiert den SVWS-Server mit dem offiziellen Linux-Installer
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
Verwendung: bash $(basename "$0") -v <Version> [-p <Passwort>]

Installiert den SVWS-Server mit dem offiziellen Linux-Installer ohne Rückfragen
(MariaDB lokal, /opt/app/svws, Port 8443) und danach die SVWS-Tools derselben
Version mit install_tools.sh (muss neben diesem Skript liegen).

Optionen:
  -v  Version des SVWS-Servers, z. B. 1.3.2 (Pflicht)
  -p  Passwort für MariaDB-Root und Keystore
      (optional, sonst wird eins mit 12 bis 16 Zeichen erzeugt und am Ende angezeigt)
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -v 1.3.2 -p svwsadmin
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

# Standard-Hilfefunktion

# Parameter auslesen
while getopts "p:v:" opt; do
  case $opt in
    p) PASSWORD="$OPTARG" ;;
    v) SVWSVERSION="$OPTARG" ;;
    *) usage ;;
  esac
done

# Pflichtfeld prüfen
if [ -z "$SVWSVERSION" ]; then
  echo "Fehler: Die Version (-v) muss angegeben werden."
  usage
fi

# Passwort optional: ohne -p eins mit 12 bis 16 Zeichen erzeugen
if [ -z "$PASSWORD" ]; then
  PW_LENGTH=$(( 12 + RANDOM % 5 ))
  PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$PW_LENGTH")
  PW_WAS_GENERATED=true
else
  PW_WAS_GENERATED=false
fi

# --- Keine Rückfragen von apt/dpkg (z. B. MariaDB Feedback-Plugin) ---
# Gilt auch für alle aufgerufenen Skripte und den SVWS-Installer
export DEBIAN_FRONTEND=noninteractive
# Frage nach dem MariaDB Feedback-Plugin vorab mit "Nein" beantworten
echo "mariadb-server mariadb-server/feedback boolean false" | debconf-set-selections

#############################################
# locales setzen 
sed -i '/^# de_DE.UTF-8 UTF-8/s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LC_ALL=de_DE.UTF-8
timedatectl set-timezone Europe/Berlin

# System-Updates und Abhängigkeiten
apt update && apt upgrade -y 
apt install -y unzip git curl net-tools wget jq

# Download des Installers
wget "https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/install-${SVWSVERSION}.sh"

# Download des SVWS-Servers 
wget -q  https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/linux-installer-${SVWSVERSION}.tar.gz

# Konfigurationsdatei (.env) erstellen
cat <<EOF > .env
CREATE_MARIADB=j
CREATE_KEYSTORE=j
MARIADB_ROOT_PASSWORD=${PASSWORD}
APP_PATH=/opt/app/svws
CONF_PATH=/etc/app/svws/conf
APP_PORT=8443
SVWS_TLS_KEYSTORE_PATH=/etc/app/svws/conf/keystore
SVWS_TLS_KEYSTORE_PASSWORD=${PASSWORD}
SVWS_TLS_KEY_ALIAS=svws
INPUT_COMMON_NAME=svws
INPUT_ORGANIZATIONAL_UNIT=svws
INPUT_ORGANIZATION=svws
INPUT_LOCALITY=NRW
INPUT_STATE=NRW
INPUT_COUNTRY=DE
validity_days=3650
EOF

# .env enthält Passwörter: nur für root lesbar
chmod 600 .env

# Installation starten
if ! bash "install-${SVWSVERSION}.sh"; then
  echo "Fehler: Die Installation des SVWS-Servers ist fehlgeschlagen."
  exit 1
fi

# SVWS-Tools derselben Version installieren (install_tools.sh neben diesem Skript)
TOOLS_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install_tools.sh"
if [ -f "$TOOLS_SCRIPT" ]; then
  if ! bash "$TOOLS_SCRIPT" -v "$SVWSVERSION"; then
    echo "Hinweis: Die SVWS-Tools ${SVWSVERSION} konnten nicht installiert werden, der SVWS-Server läuft trotzdem."
  fi
else
  echo "Hinweis: ${TOOLS_SCRIPT} nicht gefunden, die SVWS-Tools werden nicht installiert."
fi

echo "------------------------------------------------"
echo "SVWS-Server ${SVWSVERSION} installiert."
if [ "$PW_WAS_GENERATED" = true ]; then
  echo "WICHTIG: Das generierte Passwort für MariaDB-Root und Keystore lautet: $PASSWORD"
fi
echo "Das Passwort steht außerdem in $(pwd)/.env (MARIADB_ROOT_PASSWORD)."
echo "------------------------------------------------"
