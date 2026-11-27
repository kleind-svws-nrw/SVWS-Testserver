#!/bin/bash
##############################################################################
# Installiert einen All-in-one-Testserver aus den veröffentlichten Releases
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
Verwendung: bash $(basename "$0") -v <Version> [-p <Passwort>] [-d <Domain>] [-a <Passwort>]

Installiert einen All-in-one-Testserver aus den veröffentlichten Releases:
  1. SVWS-Server mit dem Linux-Installer   (install_svws_testserver.sh)
     inkl. SVWS-Tools derselben Version     (install_tools.sh)
  2. WeNoM unter Apache2, Port 443          (install_wenom_testserver.sh)
  3. WebLuPO unter nginx, Port 80           (install_weblupo_testserver.sh)
  4. Testdatenbanken aus SVWS-NRW/SVWS-TestSqlites importieren
                                            (create_svws_testdbs.sh)
  5. Benutzerkennwörter in allen Testdatenbanken setzen
                                            (generate_svws_userpasswords.sh)
  6. Übersichtsseite http://<Adresse>/ mit Links zu SVWS-Server, WeNoM,
     WebLuPO und SVWS-Tools
  7. Geschützter Testzugang http://<Adresse>/Testzugang/ (nur mit -a)

Optionen:
  -v  Version des SVWS-Servers und der SVWS-Tools, z. B. 1.5.1 (Pflicht)
  -p  Passwort für MariaDB-Root und Keystore, wird an install_svws_testserver.sh
      durchgereicht (optional, sonst erzeugt das Skript eins mit 12 bis 16 Zeichen)
  -d  Domainname des Servers für Übersichtsseite und WeNoM-Zertifikat
      (optional, sonst wird die IP-Adresse des Servers verwendet)
  -a  Passwort für den geschützten Bereich /Testzugang (Benutzer svwsadmin)
      mit den Kennwortlisten (optional, ohne -a wird kein Testzugang angelegt)
  -h  Diese Hilfe anzeigen (auch -help oder --help)

Beispiel:
  bash $(basename "$0") -v 1.5.1 -p geheim
EOF
    exit "${1:-1}"
}

# -h / -help / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "-help" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

SVWSVERSION=""
MARIADB_ROOT_PASSWORD=""
DOMAIN=""
ACCESS_PASSWORD=""

while getopts "v:p:d:a:" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        a) ACCESS_PASSWORD="$OPTARG" ;;
        v) SVWSVERSION="${OPTARG#v}" ;;
        p) MARIADB_ROOT_PASSWORD="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$SVWSVERSION" ]; then
    echo "Fehler: Die Version (-v) muss angegeben werden."
    usage
fi

# Merken, ob das Passwort mit -p angegeben wurde (sonst erzeugt es install_svws_testserver.sh)
[ -n "$MARIADB_ROOT_PASSWORD" ] && PW_GIVEN=true || PW_GIVEN=false

# Ordner dieses Skripts: hier liegen die übrigen Skripte und hier legt
# install_svws_testserver.sh die .env für den Linux-Installer ab
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for s in install_svws_testserver.sh install_tools.sh install_wenom_testserver.sh install_weblupo_testserver.sh \
         create_svws_testdbs.sh generate_svws_userpasswords.sh; do
    if [ ! -f "${SCRIPT_DIR}/${s}" ]; then
        echo "Fehler: ${s} wurde in ${SCRIPT_DIR} nicht gefunden."
        exit 1
    fi
done

# --- Gesamte Ausgabe zusätzlich in eine Logdatei schreiben ---
LOG_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install_all_in_one_$(date '+%Y%m%d_%H%M%S').log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"    # enthält Kennwörter, daher nur für root lesbar
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Protokoll der Installation: $LOG_FILE"

# Adresse des Servers: Domain, falls angegeben, sonst IP-Adresse
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_HOST="${DOMAIN:-$SERVER_IP}"

echo "Installiere All-in-one-Testserver mit Version ${SVWSVERSION} für ${SERVER_HOST}..."

#############################################
# 1. SVWS-Server mit dem Linux-Installer installieren
#    (install_svws_testserver.sh installiert danach auch die SVWS-Tools)
#############################################
# Im Skriptordner ausführen: dort entstehen die .env und die Downloads des Installers
# -p nur durchreichen, wenn es angegeben wurde
SVWS_ARGS=(-v "$SVWSVERSION")
[ -n "$MARIADB_ROOT_PASSWORD" ] && SVWS_ARGS+=(-p "$MARIADB_ROOT_PASSWORD")
echo "Starte install_svws_testserver.sh..."
if ! ( cd "$SCRIPT_DIR" && bash ./install_svws_testserver.sh "${SVWS_ARGS[@]}" ); then
    echo "Fehler: install_svws_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 2. WeNoM installieren (Apache2, nur Port 443)
#############################################
# Vor der WebLuPO, damit Port 80 bei der Apache-Installation noch frei ist
echo "Starte install_wenom_testserver.sh..."
WENOM_ARGS=(-v "$SVWSVERSION")
[ -n "$DOMAIN" ] && WENOM_ARGS+=(-d "$DOMAIN")
if ! bash "${SCRIPT_DIR}/install_wenom_testserver.sh" "${WENOM_ARGS[@]}"; then
    echo "Fehler: install_wenom_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 3. WebLuPO installieren (nginx, Port 80, unter /weblupo/)
#############################################
echo "Starte install_weblupo_testserver.sh..."
if ! bash "${SCRIPT_DIR}/install_weblupo_testserver.sh" -v "$SVWSVERSION"; then
    echo "Fehler: install_weblupo_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 4. Testdatenbanken importieren
#############################################
ENV_FILE="${SCRIPT_DIR}/.env"

# MariaDB-Root-Passwort aus der .env von install_svws_testserver.sh
# (dort steht es auch, wenn es erzeugt wurde)
MARIADB_ROOT_PASSWORD=$(grep -E '^MARIADB_ROOT_PASSWORD=' "$ENV_FILE" | tail -n 1 | cut -d '=' -f2-)

# Eigenes Zufallspasswort für den Schema-Benutzer
SCHEMA_USER="svwsadmin"
SCHEMA_PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)

# Schema-Zugang in die .env schreiben (für ein späteres Update)
grep -v -E '^TESTDB_SCHEMA_(USER|PASSWORD)=' "$ENV_FILE" > "${ENV_FILE}.tmp" || true
echo "TESTDB_SCHEMA_USER=${SCHEMA_USER}" >> "${ENV_FILE}.tmp"
echo "TESTDB_SCHEMA_PASSWORD=${SCHEMA_PASSWORD}" >> "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Warten, bis der SVWS-Server antwortet (max. 5 Minuten)
echo "Warte auf den SVWS-Server..."
for i in $(seq 1 60); do
    curl -k -s -o /dev/null "https://localhost:8443/" && break
    sleep 5
done

# Im Skriptordner ausführen: dort liegt die .env und dorthin werden die
# Testdatenbanken (SVWS-TestSqlites) geladen
echo "Starte create_svws_testdbs.sh..."
if ! ( cd "$SCRIPT_DIR" \
        && bash ./create_svws_testdbs.sh -u "$SCHEMA_USER" -p "$SCHEMA_PASSWORD" ); then
    echo "Fehler: create_svws_testdbs.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 5. Benutzerkennwörter in allen Testdatenbanken setzen
#############################################
# Ein gemeinsames neues Admin-Kennwort (12 bis 16 Zeichen) für alle Datenbanken
ADMIN_PW_LENGTH=$(( 12 + RANDOM % 5 ))
TESTDB_ADMIN_PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$ADMIN_PW_LENGTH")

# Admin-Kennwort in die .env schreiben (vorhandenen Eintrag ersetzen)
grep -v '^TESTDB_ADMIN_PASSWORD=' "$ENV_FILE" > "${ENV_FILE}.tmp" || true
echo "TESTDB_ADMIN_PASSWORD=${TESTDB_ADMIN_PASSWORD}" >> "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

PASSWORD_DIR="${SCRIPT_DIR}/Kennwoerter"
mkdir -p "$PASSWORD_DIR"
chmod 700 "$PASSWORD_DIR"

# Datenbanken = die in Schritt 4 importierten SQLite-Dateien
shopt -s nullglob
TESTDB_FILES=( "${SCRIPT_DIR}/SVWS-TestSqlites"/*.sqlite )
FAILED_DBS=()

for db_file in "${TESTDB_FILES[@]}"; do
    DB_NAME=$(basename "$db_file" .sqlite)
    echo "Setze Kennwörter in Datenbank ${DB_NAME}..."
    # Admin hat in den Testdatenbanken noch kein Kennwort, daher ist SVWS_ADMIN_PW leer
    if ! SCHEMA_NAME="$DB_NAME" \
         MARIADB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD" \
         SVWS_ADMIN="Admin" \
         SVWS_ADMIN_PW="" \
         OUTPUT_FILE="${PASSWORD_DIR}/Kennwoerter_${DB_NAME}.txt" \
         bash "${SCRIPT_DIR}/generate_svws_userpasswords.sh" -np "$TESTDB_ADMIN_PASSWORD"; then
        FAILED_DBS+=("$DB_NAME")
    fi
done
chmod 600 "$PASSWORD_DIR"/*.txt 2>/dev/null || true

if [ ${#FAILED_DBS[@]} -gt 0 ]; then
    echo "Hinweis: In folgenden Datenbanken gab es Fehler beim Setzen der Kennwörter: ${FAILED_DBS[*]}"
fi

#############################################
# 6. Übersichtsseite /var/www/html/index.html erzeugen
#############################################
INDEX_FILE="/var/www/html/index.html"
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M')

echo "Erzeuge Übersichtsseite ${INDEX_FILE} für ${SERVER_HOST}..."
mkdir -p "$(dirname "$INDEX_FILE")"
cat > "$INDEX_FILE" <<EOF
<!DOCTYPE html>
<html lang="de">
<head>
    <title>${SERVER_HOST} - Testplattform</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta charset="UTF-8">
    <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
    <style>
        .header-bg { background-color: #003462; color: white; }
    </style>
</head>
<body>

<header class="w3-container header-bg">
    <div class="w3-row">
        <div class="w3-half w3-container">
            <h1><a href="https://www.svws.nrw.de/" style="text-decoration:none;">SVWS-Server</a></h1>
            <h4>Testplattform</h4>
        </div>
        <div class="w3-half w3-container">
            <img src="logo_nrw.jpg" alt="NRW Logo" height="150" class="w3-right w3-padding-16">
        </div>
    </div>
</header>

<main class="w3-container w3-padding-large">

    <section>
        <h3>SVWS-Server, WeNoM und WebLuPO</h3>
        <p><b>Testserver</b> – ausschließlich für Testzwecke vorgesehen!</p>
        <p>Diese Versionen befinden sich noch in der Testphase und<br>
        sind <b>nicht für den produktiven Einsatz</b> geeignet.</p>
        <p><b>VERSION ${SVWSVERSION} - INSTALLIERT ${INSTALL_DATE}</b></p>
    </section>

    <section>
        <table class="w3-table w3-bordered w3-hoverable">
            <thead>
                <tr class="w3-light-grey">
                    <th>Test Server</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>SVWS-Server: <a href="https://${SERVER_HOST}:8443/">https://${SERVER_HOST}:8443</a></td>
                </tr>
                <tr>
                    <td>SVWS-WeNoM: <a href="https://${SERVER_HOST}/">https://${SERVER_HOST}</a></td>
                </tr>
                <tr>
                    <td>SVWS-WebLuPO: <a href="http://${SERVER_HOST}/weblupo/">http://${SERVER_HOST}/weblupo/</a></td>
                </tr>
                 <tr>
                    <td>SVWS-Tools: <a href="https://${SERVER_HOST}:8443/app/start">https://${SERVER_HOST}:8443/app/start</a></td>
                </tr>
            </tbody>
        </table>
    </section>

</main>
</body>
</html>
EOF
chown www-data:www-data "$INDEX_FILE"
chmod 644 "$INDEX_FILE"

# NRW-Logo für die Übersichtsseite herunterladen
LOGO_FILE="/var/www/html/logo_nrw.jpg"
if wget -q -O "$LOGO_FILE" https://www.land.nrw/media/12370/download; then
    chown www-data:www-data "$LOGO_FILE"
    chmod 644 "$LOGO_FILE"
else
    rm -f "$LOGO_FILE"
    echo "Hinweis: Das NRW-Logo konnte nicht geladen werden, die Übersichtsseite zeigt dann nur den Alternativtext."
fi

# Standard-Startseite von nginx löschen
rm -f /var/www/html/index.nginx-debian.html

#############################################
# 7. Geschützten Testzugang /var/www/html/Testzugang einrichten (nur mit -a)
#############################################
# Der Ordner enthält Kennwörter und wird per nginx mit Benutzer/Passwort
# geschützt (Basic Auth). Die Verschlüsselung übernimmt der vorgeschaltete
# Reverse-Proxy.
TESTZUGANG_DIR="/var/www/html/Testzugang"
TESTZUGANG_USER="svwsadmin"
TESTZUGANG_HTPASSWD="/etc/nginx/.htpasswd-testzugang"
TESTZUGANG_SNIPPET="/etc/nginx/snippets/testzugang.conf"
NGINX_SITE="/etc/nginx/sites-available/default"
TESTZUGANG_INCLUDE="include ${TESTZUGANG_SNIPPET};"

if [ -z "$ACCESS_PASSWORD" ]; then
    # Ohne -a keinen Testzugang - auch Reste eines früheren Laufs entfernen
    echo "Kein Passwort mit -a angegeben: Es wird kein Testzugang eingerichtet."
    rm -rf "$TESTZUGANG_DIR"
    rm -f "$TESTZUGANG_HTPASSWD" "$TESTZUGANG_SNIPPET"
    sed -i "\\|${TESTZUGANG_INCLUDE}|d" "$NGINX_SITE"
    nginx -t && systemctl reload nginx
else
mkdir -p "$TESTZUGANG_DIR"
rm -f "$TESTZUGANG_DIR"/*

# Kennwortlisten aller Testdatenbanken kopieren
cp "$PASSWORD_DIR"/Kennwoerter_*.txt "$TESTZUGANG_DIR"/ 2>/dev/null || true

# Datei mit den MariaDB-Zugangsdaten
cat > "${TESTZUGANG_DIR}/MariaDB.txt" <<EOF
MariaDB-Zugang auf ${SERVER_HOST} (Port 3306)

Root-Benutzer:   root
Root-Passwort:   ${MARIADB_ROOT_PASSWORD}

Schema-Benutzer der Testdatenbanken: ${SCHEMA_USER}
Passwort:                            ${SCHEMA_PASSWORD}
EOF

# Client-Secret des WeNoM (für die Synchronisation mit dem SVWS-Server)
WENOM_SECRET_FILE="/var/www/html/wenom/db/client.sec"
if [ -f "$WENOM_SECRET_FILE" ]; then
    cat "$WENOM_SECRET_FILE" > "${TESTZUGANG_DIR}/wenom_credential.txt"
else
    echo "Hinweis: ${WENOM_SECRET_FILE} nicht gefunden, wenom_credential.txt wird nicht angelegt."
fi

# Tabellenzeilen für alle Dateien erzeugen
# (MariaDB und WeNoM zuerst, dann die Kennwortlisten alphabetisch)
TESTZUGANG_ROWS=""
while IFS= read -r FILE; do
    TESTZUGANG_ROWS+="                <tr>
                    <td><a href=\"${FILE}\">${FILE}</a></td>
                </tr>
"
done < <(find "$TESTZUGANG_DIR" -maxdepth 1 -type f -name '*.txt' -printf '%f\n' \
         | sort | awk '$0=="MariaDB.txt"{m=$0; next} $0=="wenom_credential.txt"{w=$0; next}
                      {rest=rest $0 "\n"}
                      END{if(m!="")print m; if(w!="")print w; printf "%s", rest}')

cat > "${TESTZUGANG_DIR}/index.html" <<EOF
<!DOCTYPE html>
<html lang="de">
<head>
    <title>${SERVER_HOST} - Testzugang</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta charset="UTF-8">
    <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
    <style>
        .header-bg { background-color: #003462; color: white; }
    </style>
</head>
<body>

<header class="w3-container header-bg">
    <div class="w3-row">
        <div class="w3-half w3-container">
            <h1><a href="../" style="text-decoration:none;">SVWS-Server</a></h1>
            <h4>Testzugang</h4>
        </div>
        <div class="w3-half w3-container">
            <img src="../logo_nrw.jpg" alt="NRW Logo" height="150" class="w3-right w3-padding-16">
        </div>
    </div>
</header>

<main class="w3-container w3-padding-large">

    <section>
        <p>Zugangsdaten für diesen Testserver – <b>nur für Test- und Schulungszwecke!</b><br>
        Es werden keine personenbezogenen Daten verwendet:<br>
        Alle Daten sind generiert bzw. anonymisiert.</p>
        <p>Der Benutzer <b>Admin</b> hat in allen Testdatenbanken dasselbe Kennwort: <b>${TESTDB_ADMIN_PASSWORD}</b></p>
    </section>

    <section>
        <table class="w3-table w3-bordered w3-hoverable">
            <thead>
                <tr class="w3-light-grey">
                    <th>Zugangsdaten</th>
                </tr>
            </thead>
            <tbody>
${TESTZUGANG_ROWS}            </tbody>
        </table>
    </section>

</main>
</body>
</html>
EOF

chown -R www-data:www-data "$TESTZUGANG_DIR"
find "$TESTZUGANG_DIR" -type f -exec chmod 644 {} +
chmod 755 "$TESTZUGANG_DIR"

# --- Zugriffsschutz in nginx ---
# Passwortdatei (APR1-Hash, wie htpasswd) für den Benutzer svwsadmin
command -v openssl &> /dev/null || apt install -y openssl
printf '%s:%s\n' "$TESTZUGANG_USER" "$(openssl passwd -apr1 "$ACCESS_PASSWORD")" > "$TESTZUGANG_HTPASSWD"
chown root:www-data "$TESTZUGANG_HTPASSWD"
chmod 640 "$TESTZUGANG_HTPASSWD"

# Schutzregel als eigene Datei, die in der nginx-Standardseite eingebunden wird
mkdir -p "$(dirname "$TESTZUGANG_SNIPPET")"
cat > "$TESTZUGANG_SNIPPET" <<EOF
# Geschützter Testzugang (angelegt von install_all_in_one_fromScratch.sh)
location ^~ /Testzugang {
    auth_basic "Testzugang";
    auth_basic_user_file ${TESTZUGANG_HTPASSWD};
}
EOF

# Einbinden direkt nach "server_name _;" der Standardseite (nur einmal)
if ! grep -qF "$TESTZUGANG_INCLUDE" "$NGINX_SITE"; then
    sed -i "0,/^[[:space:]]*server_name _;/s||&\n\t${TESTZUGANG_INCLUDE}|" "$NGINX_SITE"
fi

if nginx -t; then
    systemctl reload nginx
    echo "Testzugang eingerichtet: http://${SERVER_HOST}/Testzugang/ (Benutzer: ${TESTZUGANG_USER})"
else
    echo "Fehler: Die nginx-Konfiguration für den Testzugang ist fehlerhaft."
    exit 1
fi
fi

#############################################
# TODO: weitere Installationsschritte
#############################################

echo "------------------------------------------------"
echo "Installation abgeschlossen (Version ${SVWSVERSION})."
if [ "$PW_GIVEN" = false ]; then
    # Von install_svws_testserver.sh erzeugt - in Schritt 4 aus der .env gelesen
    echo "WICHTIG: Das generierte MariaDB-Root-Passwort lautet: $MARIADB_ROOT_PASSWORD"
fi
echo "MariaDB-Root-Passwort gespeichert in: ${SCRIPT_DIR}/.env"
echo "Testdatenbanken: Schema-Benutzer '$SCHEMA_USER', Passwort: $SCHEMA_PASSWORD"
echo "SVWS-Benutzer 'Admin' in allen Testdatenbanken, Passwort: $TESTDB_ADMIN_PASSWORD"
echo "Kennwörter aller übrigen Benutzer: ${PASSWORD_DIR}/Kennwoerter_<Datenbank>.txt"
echo "Übersichtsseite: http://${SERVER_HOST}/"
if [ -n "$ACCESS_PASSWORD" ]; then
    echo "Testzugang (Kennwörter): http://${SERVER_HOST}/Testzugang/ - Benutzer ${TESTZUGANG_USER}, Passwort aus -a"
fi
echo "Protokoll der Installation: $LOG_FILE"
echo "------------------------------------------------"
