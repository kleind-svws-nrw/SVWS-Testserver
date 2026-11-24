#!/bin/bash
##############################################################################
# Installiert WebLuPO unter Apache2
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

Installiert nginx in der Standardkonfiguration (Port 80, Wurzel /var/www/html)
und richtet die WebLuPO unter /var/www/html/weblupo ein
(erreichbar unter http://<Server-IP>/weblupo/).

Optionen:
  -v  Version des SVWS-Servers, z. B. 1.3.2 (Pflicht)
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -v 1.3.2
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

# Parameter-Abfrage mit getopts
while getopts "v:" opt; do
  case $opt in
    v) SVWSVERSION=$OPTARG ;;
    *) usage ;;
  esac
done

# Verpflichtende Prüfung der SVWS-Version
if [ -z "$SVWSVERSION" ]; then
    echo -e "\e[31mFehler: Die SVWS-Version (-v) muss angegeben werden!\e[0m"
    echo "Beispiel: $0 -v 1.2.2"
    exit 1
fi

DOWNLOADPATH=https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/SVWS-Laufbahnplanung-${SVWSVERSION}.zip

echo "Starte Installation von WebLuPo $SVWSVERSION auf $INSTALLPATH..."

#############################################
# locales setzen 
sed -i '/^# de_DE.UTF-8 UTF-8/s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LC_ALL=de_DE.UTF-8
timedatectl set-timezone Europe/Berlin

### Prüfen, ob Port 80 schon von einem anderen Dienst belegt ist (z. B. Apache2)
if ss -ltnp 2>/dev/null | grep -E ':80[[:space:]]' | grep -vq nginx; then
    echo -e "\e[31mFehler: Port 80 wird bereits von einem anderen Dienst verwendet:\e[0m"
    ss -ltnp | grep -E ':80[[:space:]]'
    echo "Bitte diesen Dienst zuerst auf Port 80 abschalten (bei Apache2: 'Listen 80' in /etc/apache2/ports.conf auskommentieren)."
    exit 1
fi

### nginx installation
apt update && apt upgrade -y
apt install -y curl wget zip unzip dnsutils nmap net-tools nano mc ca-certificates gnupg2 lsb-release openssl apt-transport-https gnupg nginx

# Download und Entpacken
echo "Download und Entpacken WebLuPo von $DOWNLOADPATH"
mkdir -p "$INSTALLPATH"
TMPZIP=$(mktemp --suffix=.zip)
wget -O "$TMPZIP" "$DOWNLOADPATH"
unzip -o "$TMPZIP" -d "$INSTALLPATH"
rm -f "$TMPZIP"
chown -R www-data:www-data "$INSTALLPATH"

# Konfiguration testen und nginx (neu) starten
nginx -t
systemctl enable nginx
systemctl restart nginx

SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "\n\n################# Installation WebLuPo beendet! ####################\n"
echo "Die WebLuPO ist erreichbar unter: http://${SERVER_IP}/weblupo/"
