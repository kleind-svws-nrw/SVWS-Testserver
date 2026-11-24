#!/bin/bash
##############################################################################
# Installiert WeNoM unter Apache2
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
Verwendung: bash $(basename "$0") -v <Version> [-d <Domain>]

Installiert Apache2 mit PHP und richtet den WeNoM unter /var/www/html/wenom ein.
Nur HTTPS auf Port 443 mit selbstsigniertem Zertifikat, Port 80 wird abgeschaltet.
Am Ende wird das Client-Secret angezeigt.

Optionen:
  -v  Version des SVWS-Servers, z. B. 1.3.3 (Pflicht)
  -d  Domainname für Zertifikat und VirtualHost (optional, sonst nur die IP)
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -v 1.3.3 -d wenom.meineschule.de
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

DOMAIN=""
PHPVERSION=8.4
INSTALLPATH=/var/www/html/wenom

# Parameter-Abfrage mit getopts
while getopts "v:d:" opt; do
  case $opt in
    v) SVWSVERSION=$OPTARG ;;
    d) DOMAIN=$OPTARG ;;
    *) usage ;;
  esac
done

# Verpflichtende Prüfung der SVWS-Version
if [ -z "$SVWSVERSION" ]; then
    echo -e "\e[31mFehler: Die SVWS-Version (-v) muss angegeben werden!\e[0m"
    echo "Beispiel: $0 -v 1.2.2"
    exit 1
fi


DOWNLOADPATH=https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/WeNoM-${SVWSVERSION}.zip

# Domain optional - Fallback auf Server-IP
if [ -z "$DOMAIN" ]; then
    # Ermittelt die primäre öffentliche/lokale IP-Adresse
    DOMAIN=$(hostname -I | awk '{print $1}')
    echo "Keine Domain angegeben. Nutze IP-Adresse: $DOMAIN"
    USEIP=true
fi


echo "Starte Installation von WeNoM $SVWSVERSION auf $DOMAIN..."

#############################################
# locales setzen 
sed -i '/^# de_DE.UTF-8 UTF-8/s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LC_ALL=de_DE.UTF-8
timedatectl set-timezone Europe/Berlin

### Apache2 und PHP installation
apt update && apt upgrade -y
apt install -y curl zip unzip dnsutils nmap net-tools nano mc ca-certificates gnupg2 lsb-release openssl apt-transport-https gnupg
apt install -y apache2 libapache2-mod-security2 php${PHPVERSION} php${PHPVERSION}-fpm php${PHPVERSION}-sqlite3

a2enmod proxy_fcgi setenvif rewrite headers ssl
a2enconf php${PHPVERSION}-fpm

# PHP Config anpassen
sed -i "s|;extension=pdo_sqlite.*$|extension=pdo_sqlite|" /etc/php/${PHPVERSION}/fpm/php.ini

# Verzeichnis-Berechtigungen in Apache setzen
if ! grep -q "<Directory ${INSTALLPATH}>" /etc/apache2/apache2.conf; then
echo "
<Directory ${INSTALLPATH}>
   Options Indexes FollowSymLinks Includes ExecCGI
   AllowOverride All
   Require all granted
</Directory>" >> /etc/apache2/apache2.conf
fi

### Port 80 komplett abschalten - WeNoM läuft nur über HTTPS (Port 443)
# "Listen 80" in der ports.conf mit # auskommentieren
sed -i -E 's/^([[:space:]]*Listen[[:space:]]+80)[[:space:]]*$/#\1/' /etc/apache2/ports.conf
# Standard-Site 000-default löschen (Link in sites-enabled und Datei in sites-available)
rm -f /etc/apache2/sites-enabled/000-default.conf
rm -f /etc/apache2/sites-available/000-default.conf

### SSL VHost konfigurieren
a2ensite default-ssl.conf
mkdir -p ${INSTALLPATH}/public

# DocumentRoot und ServerName in der SSL-Config setzen
sed -i "s|DocumentRoot.*$|DocumentRoot ${INSTALLPATH}/public|" /etc/apache2/sites-available/default-ssl.conf
if ! grep -q "ServerName" /etc/apache2/sites-available/default-ssl.conf; then
    sed -i "/DocumentRoot/a \ \ \ \ ServerName ${DOMAIN}" /etc/apache2/sites-available/default-ssl.conf
fi

# Vorbereitung der Zertifikats-Pfade
CERT_KEY="/etc/ssl/private/wenomtest-selfsigned.key"
CERT_CRT="/etc/ssl/certs/wenomtest-selfsigned.crt"
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "Generiere selbstsigniertes Zertifikat..."

if [ "$USEIP" = true ]; then
    # Nur IP im Zertifikat
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$CERT_KEY" -out "$CERT_CRT" \
        -subj "/C=DE/ST=NRW/L=NRW/O=NONE/CN=${SERVER_IP}" \
        -addext "subjectAltName = IP:${SERVER_IP}"
else
    # Domain UND IP im Zertifikat (Best Practice)
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$CERT_KEY" -out "$CERT_CRT" \
        -subj "/C=DE/ST=NRW/L=NRW/O=NONE/CN=${DOMAIN}" \
        -addext "subjectAltName = DNS:${DOMAIN}, IP:${SERVER_IP}"
fi

# Apache auf die neuen Zertifikats-Dateien hinweisen
sed -i "s|SSLCertificateFile.*|SSLCertificateFile ${CERT_CRT}|" /etc/apache2/sites-available/default-ssl.conf
sed -i "s|SSLCertificateKeyFile.*|SSLCertificateKeyFile ${CERT_KEY}|" /etc/apache2/sites-available/default-ssl.conf

# Apache testen und neustarten
apache2ctl configtest
a2enmod security2

systemctl restart apache2
systemctl restart php${PHPVERSION}-fpm

# Download und Entpacken 
mkdir -p $INSTALLPATH
echo "Download und Entpacken Wenom von $DOWNLOADPATH"
cd $INSTALLPATH
wget $DOWNLOADPATH
unzip -o *.zip


# Rechte setzen
chmod -R 755 $INSTALLPATH
chown -R www-data:www-data $INSTALLPATH
# DB Verzeichnis braucht Schreibrechte für SQLite
mkdir -p $INSTALLPATH/db
chmod -R 777 $INSTALLPATH/db 

# Erzeugen des Secrets
echo "Generiere Client-Secret..."
# Wir nutzen --insecure (-k), falls das SSL-Zertifikat self-signed ist
curl -k --request GET --url "https://localhost/api/setup" --header "Content-Type: application/x-www-form-urlencoded"

echo -e "\n\nDas Secret für die Synchronisation mit dem SVWS-Server ist:\n"
if [ -f "${INSTALLPATH}/db/client.sec" ]; then
    cat ${INSTALLPATH}/db/client.sec
else
    echo "Fehler: client.sec wurde nicht erstellt."
fi

echo -e "\n\n################# Installation auf $DOMAIN beendet! ####################\n"
