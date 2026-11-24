#!/bin/bash
##############################################################################
# Erzeugt mehrere WeNoM-Instanzen (Datenbankordner + Apache-VHosts)
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

# =========================
# KONFIGURATION
# =========================
DB_FOLDER="/var/www/html/db"
WEBROOT="/var/www/html/public"
APACHE_CONF_DIR="/etc/apache2/sites-available"

SSL_CERT="/etc/ssl/certs/wenomtest-selfsigned.crt"
SSL_KEY="/etc/ssl/private/wenomtest-selfsigned.key"

# =========================
# PARAMETER
# =========================
COUNT=""
URL=""

usage() {
    echo "Verwendung: $0 -n <Anzahl> -url <Domain>"
    echo "Beispiel: $0 -n 15 -url schule.de"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n)
            COUNT="$2"
            shift 2
            ;;
        -url)
            URL="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# =========================
# VALIDIERUNG
# =========================
[[ -z "$COUNT" ]] && usage
[[ -z "$URL" ]] && usage

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
    echo "Fehler: -n muss eine Zahl sein"
    exit 1
fi

# =========================
# ERSTELLUNG
# =========================
echo "Erzeuge $COUNT WeNoM Instanzen für Domain: $URL"

for ((i=1; i<=COUNT; i++)); do

    DBDIR="${DB_FOLDER}/wenom${i}"
    CONF_FILE="wenom${i}.${URL}.conf"
    CONF_PATH="${APACHE_CONF_DIR}/${CONF_FILE}"
    SERVERNAME="wenom${i}.${URL}"

    mkdir -p "$DBDIR"

    cat > "$CONF_PATH" <<EOF
<VirtualHost *:443>
    ServerName ${SERVERNAME}

    DocumentRoot ${WEBROOT}

    SSLEngine on
    SSLCertificateFile ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}

    ErrorLog \${APACHE_LOG_DIR}/${SERVERNAME}.error.log
    CustomLog \${APACHE_LOG_DIR}/${SERVERNAME}.access.log combined

    <FilesMatch "\.(?:cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>
    <Directory /usr/lib/cgi-bin>
        SSLOptions +StdEnvVars
    </Directory>

    SetEnv ENM_DB_DIR ${DB_FOLDER}/wenom${i}

</VirtualHost>
EOF

    echo "OK erstellt: $CONF_FILE"

    # VHost aktivieren
    a2ensite "$CONF_FILE" >/dev/null 2>&1

done

chown -R www-data:www-data /var/www/html
chmod -R 777 ${DB_FOLDER}

echo "Reload Apache..."
systemctl reload apache2

echo "Fertig."