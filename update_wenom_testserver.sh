#!/bin/bash
##############################################################################
# Spielt WeNoM neu ein (löscht alle WeNoM-Daten)
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
Verwendung: bash $(basename "$0") -v <Version> [-y] [-c [-d <Domain>]]
       bash $(basename "$0") -c [-d <Domain>]

Spielt den WeNoM unter /var/www/html/wenom neu ein (mit -v).
ACHTUNG: Dabei werden alle WeNoM-Daten gelöscht!
Nur mit -c (ohne -v) wird ausschließlich das Zertifikat erneuert,
die WeNoM-Installation und ihre Daten bleiben unverändert.

Optionen:
  -v  Version des SVWS-Servers, z. B. 1.3.3 (Pflicht, außer bei nur -c)
  -y  Ohne Sicherheitsabfrage ausführen
  -c  Selbstsigniertes Zertifikat neu erzeugen (10 Jahre gültig)
  -d  Domainname für das neue Zertifikat (nur mit -c, sonst nur die IP)
  -h  Diese Hilfe anzeigen

Beispiele:
  bash $(basename "$0") -v 1.3.3 -y
  bash $(basename "$0") -v 1.3.3 -y -c -d wenom.meineschule.de
  bash $(basename "$0") -c -d wenom.meineschule.de     # nur Zertifikat
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

INSTALLPATH=/var/www/html/wenom
SVWSVERSION=""

# Parameter auswerten
AUTO_YES=false
NEW_CERT=false
DOMAIN=""

while getopts "v:ycd:" opt; do
    case "$opt" in
        v)
            SVWSVERSION="$OPTARG"
            ;;
        y)
            AUTO_YES=true
            ;;
        c)
            NEW_CERT=true
            ;;
        d)
            DOMAIN="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

# -v ist Pflicht, außer es soll nur das Zertifikat erneuert werden (-c)
if [ -z "$SVWSVERSION" ] && [ "$NEW_CERT" = false ]; then
    echo -e "\e[31mFehler: Die SVWS-Version (-v) muss angegeben werden (oder -c für nur das Zertifikat)!\e[0m"
    usage
fi

if [ -n "$SVWSVERSION" ]; then
    DO_UPDATE=true
else
    DO_UPDATE=false
    echo "Kein -v angegeben: Es wird nur das Zertifikat erneuert, der WeNoM bleibt unverändert."
fi

if [ -n "$DOMAIN" ] && [ "$NEW_CERT" = false ]; then
    echo "Hinweis: -d wirkt nur zusammen mit -c und wird ignoriert."
fi

########### WeNoM neu einspielen (nur mit -v) ###########
if [ "$DO_UPDATE" = true ]; then
    DOWNLOADPATH="https://github.com/SVWS-NRW/SVWS-Server/releases/download/v${SVWSVERSION}/WeNoM-${SVWSVERSION}.zip"

    # Sicherheitsabfrage nur ohne -y
    if [ "$AUTO_YES" = false ]; then
        echo "Achtung!"
        echo "Es wird WeNoM ${SVWSVERSION} installiert."
        [ "$NEW_CERT" = true ] && echo "Außerdem wird ein neues Zertifikat erzeugt."
        echo "Das Update überschreibt die bestehende Installation"
        echo "und löscht alle Datenbankeinträge."
        echo "Bitte vorher ein Backup erstellen!"
        echo

        read -rp "Wollen Sie wirklich alle Daten löschen? [y/N] " antwort

        case "$antwort" in
            [yY]|[yY][eE][sS])
                echo "Update wird gestartet..."
                ;;
            *)
                echo "Update abgebrochen."
                exit 0
                ;;
        esac
    fi

    # System-Update
    apt update && apt upgrade -y && apt autoremove -y

    # Verzeichnisse vorbereiten

    ########## optional: Datenbank sichern in root ordner ###########
    # cp "$INSTALLPATH/db/app.sqlite" "/root/app.sqlite.backup.$(date +%Y%m%d_%H%M%S)"
    rm -rf "$INSTALLPATH"/*
    cd "$INSTALLPATH" || exit 1
    wget -O wenom.zip "$DOWNLOADPATH"
    unzip -q wenom.zip

    # Berechtigungen sicher setzen
    chown -R www-data:www-data "$INSTALLPATH"
    find "$INSTALLPATH" -type d -exec chmod 755 {} +
    find "$INSTALLPATH" -type f -exec chmod 644 {} +

    # API-Setup triggern
    curl -k --request GET --url https://localhost/api/setup \
         --header "Content-Type: application/x-www-form-urlencoded"

    echo -e "\nDas Secret zum Verbinden mit dem SVWS Server ist:\n"
    cat "$INSTALLPATH/db/client.sec"
    echo ""

    ########### optional: Das secret des Testservers bereitstellen ############
    # mkdir -p /var/www/html/secret
    #echo -e "\n\n!!! Achtung: Das Secret wird unter https://URL/secret.html veröffentlicht !!!"
    #echo "!!! Nur für Testzwecke geeignet !!!"
    #echo
    # cat "$INSTALLPATH/db/client.sec" > /var/www/html/secret/secret.html

    ########### optional: eingerichtete DB-User wieder zurück kopieren ###########
    #cp /root/app.sqlite.backup "$INSTALLPATH/db/app.sqlite"

    chown -R www-data:www-data $INSTALLPATH
fi

########### optional (-c): Zertifikat neu erzeugen ###########
if [ "$NEW_CERT" = true ]; then
    SSL_CONF="/etc/apache2/sites-available/default-ssl.conf"
    CERT_KEY="/etc/ssl/private/wenomtest-selfsigned.key"
    CERT_CRT="/etc/ssl/certs/wenomtest-selfsigned.crt"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    USEIP=false

    # Domain optional - Fallback auf Server-IP
    if [ -z "$DOMAIN" ]; then
        DOMAIN="$SERVER_IP"
        echo "Keine Domain angegeben. Nutze IP-Adresse: $DOMAIN"
        USEIP=true
    fi

    # ServerName setzen: vorhandenen Eintrag ersetzen, sonst nach DocumentRoot einfügen
    if grep -q "^[[:space:]]*ServerName" "$SSL_CONF"; then
        sed -i "s|^\([[:space:]]*\)ServerName.*|\1ServerName ${DOMAIN}|" "$SSL_CONF"
    else
        sed -i "/DocumentRoot/a \ \ \ \ ServerName ${DOMAIN}" "$SSL_CONF"
    fi

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
    sed -i "s|SSLCertificateFile.*|SSLCertificateFile ${CERT_CRT}|" "$SSL_CONF"
    sed -i "s|SSLCertificateKeyFile.*|SSLCertificateKeyFile ${CERT_KEY}|" "$SSL_CONF"

    # Apache testen und neustarten
    if apache2ctl configtest; then
        systemctl restart apache2
        echo -e "\n################# Zertifikat für $DOMAIN neu generiert! ####################\n"
    else
        echo "Fehler: Die Apache-Konfiguration ist fehlerhaft, Apache wurde nicht neu gestartet."
        exit 1
    fi
fi

if [ "$DO_UPDATE" = true ]; then
    echo "Deployment erfolgreich abgeschlossen!"
else
    echo "Zertifikat erfolgreich erneuert!"
fi
