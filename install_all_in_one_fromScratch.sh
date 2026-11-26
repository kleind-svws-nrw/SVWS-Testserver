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
Verwendung: bash $(basename "$0") [-m <ServerMode>] [-b <Branch>] [-p <Passwort>] [-v <Version>] [-d <Domain>] [-a <Passwort>]

Installiert einen All-in-one-Testserver. Der SVWS-Server wird aus einem
GitHub-Branch gebaut (Ordner SVWS-Server neben dem Skriptordner) und mit dem
dabei erzeugten Linux-Installer nach /opt/app/svws installiert (Port 8443).
Die Antworten für den Installer inkl. MariaDB-Root-Passwort stehen in der
Datei .env im Skriptordner.

Optionen:
  -m  ServerMode, z. B. dev, alpha, beta, stable (optional, Standard: dev)
  -b  Git-Branch, z. B. dev oder master (optional, Standard: dev)
  -p  Passwort für MariaDB-Root und Keystore (optional, sonst Zufallsgenerierung)
  -v  Release-Version für WeNoM, WebLuPO und SVWS-Tools, z. B. 1.5.1
      (optional, Standard: neueste Version von github.com/SVWS-NRW/SVWS-Server/releases)
  -d  Domainname des Servers für Übersichtsseite und WeNoM-Zertifikat
      (optional, sonst wird die IP-Adresse des Servers verwendet)
  -a  Passwort für den geschützten Bereich /Testzugang (Benutzer svwsadmin)
      mit den Kennwortlisten (optional, ohne -a wird kein Testzugang angelegt)
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
DOMAIN=""
ACCESS_PASSWORD=""

# Parameter mit getopts einlesen
while getopts "p:b:m:v:d:a:" opt; do
  case $opt in
    a) ACCESS_PASSWORD="$OPTARG" ;;
    d) DOMAIN="$OPTARG" ;;
    v) SVWSVERSION="${OPTARG#v}" ;;
    p) MARIADB_ROOT_PASSWORD="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    m) SERVERMODE="$OPTARG" ;;
    *) usage ;;
  esac
done

# --- Gesamte Ausgabe (inkl. Fehlermeldungen) zusätzlich in eine Logdatei schreiben ---
LOG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install_all_in_one_$(date '+%Y%m%d_%H%M%S').log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"    # enthält Kennwörter, daher nur für root lesbar
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Protokoll der Installation: $LOG_FILE"

# --- Keine Rückfragen von apt/dpkg (z. B. MariaDB Feedback-Plugin) ---
# Gilt auch für alle aufgerufenen Skripte und den SVWS-Installer
export DEBIAN_FRONTEND=noninteractive
# Frage nach dem MariaDB Feedback-Plugin vorab mit "Nein" beantworten
echo "mariadb-server mariadb-server/feedback boolean false" | debconf-set-selections

# Fallback, falls -b oder -m mit leerem Wert übergeben wurden
[ -z "$BRANCH" ] && BRANCH="dev"
[ -z "$SERVERMODE" ] && SERVERMODE="dev"
echo "Verwende Branch: $BRANCH, ServerMode: $SERVERMODE"

# Adresse des Servers: Domain, falls angegeben, sonst IP-Adresse
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_HOST="${DOMAIN:-$SERVER_IP}"
echo "Verwende Serveradresse: $SERVER_HOST"

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
# 2. SVWS-Server aus dem GitHub-Branch bauen
#############################################
TEMURINVERSION="temurin-21-jdk"
# Git-Klon direkt neben dem Installationsverzeichnis (Ordner SVWS-Server)
SVWS_DIR="$(dirname "$SCRIPTS_DIR")/SVWS-Server"
LINUX_DIST_DIR="${SVWS_DIR}/deployment/linux-installer/build/distributions"
WENOM_BUILD_DIR="${SVWS_DIR}/svws-webclient/enmserver/build"
WEBLUPO_BUILD_DIR="${SVWS_DIR}/svws-webclient/laufbahnplanung/build"

# Nicht passende Muster ergeben eine leere Liste statt des Musters selbst
shopt -s nullglob

echo "Baue den SVWS-Server (Branch: $BRANCH) in ${SVWS_DIR}..."

# --- Sprache und Zeitzone ---
sed -i '/^# de_DE.UTF-8 UTF-8/s/^# //' /etc/locale.gen
locale-gen
update-locale LANG=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LC_ALL=de_DE.UTF-8
timedatectl set-timezone Europe/Berlin

# --- Pakete und Java (Adoptium) ---
apt update && apt upgrade -y
# libatomic1 wird von dem Node.js benötigt, das Gradle für den Webclient-Build lädt;
# unzip, curl, net-tools und jq braucht der Linux-Installer
apt install -y wget apt-transport-https gpg git zip unzip curl net-tools jq libatomic1
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list
apt update
apt install -y "$TEMURINVERSION"

# --- Quellen holen ---
if [ ! -d "${SVWS_DIR}/.git" ]; then
    git clone https://github.com/SVWS-NRW/SVWS-Server "$SVWS_DIR"
fi
git -C "$SVWS_DIR" switch "$BRANCH"

# --- Bauen: Server (ohne Tests, mit explizitem OpenAPI-Schritt) und Linux-Installer ---
# Build-Artefakte früherer Läufe entfernen, damit später nur die neuen verwendet werden
rm -f "$LINUX_DIST_DIR"/install-* "$LINUX_DIST_DIR"/linux-installer-* \
      "$WENOM_BUILD_DIR"/WeNoM-* "$WEBLUPO_BUILD_DIR"/SVWS-Laufbahnplanung-*

if ! ( cd "$SVWS_DIR" \
        && ./gradlew :svws-openapi:assembleTranspiled build -x test \
        && ./gradlew buildLinuxInstaller ); then
    echo "Fehler: Der Gradle-Build in ${SVWS_DIR} ist fehlgeschlagen."
    exit 1
fi

# todo: buildWindowsInstaller - variablen für gradle setzen
# ( cd "$SVWS_DIR" && ./gradlew buildWindowsInstaller )

#############################################
# 3. Build-Dateien bereitstellen
#############################################
DOWNLOAD_DIR="/var/www/html/download"

# Tatsächlich gebauten Branch für die Übersichtsseite merken
BUILD_BRANCH=$(git -C "$SVWS_DIR" branch --show-current 2>/dev/null)
BUILD_BRANCH="${BUILD_BRANCH:-$BRANCH}"
BUILD_DATE=$(date '+%Y-%m-%d %H:%M')

# Build-Dateien ins Download-Verzeichnis kopieren (alte Dateien vorher entfernen)
BUILD_FILES=( "$LINUX_DIST_DIR"/install-* "$LINUX_DIST_DIR"/linux-installer-* \
              "$WENOM_BUILD_DIR"/WeNoM-* "$WEBLUPO_BUILD_DIR"/SVWS-Laufbahnplanung-* )
mkdir -p "$DOWNLOAD_DIR"
rm -f "$DOWNLOAD_DIR"/*
if [ ${#BUILD_FILES[@]} -gt 0 ]; then
    echo "Kopiere ${#BUILD_FILES[@]} Build-Dateien nach ${DOWNLOAD_DIR}..."
    cp "${BUILD_FILES[@]}" "$DOWNLOAD_DIR"/
else
    echo "Hinweis: Es wurden keine Build-Dateien gefunden, das Download-Verzeichnis bleibt leer."
fi

#############################################
# 4. SVWS-Server mit dem gebauten Linux-Installer installieren
#############################################
# Wie install_svws_testserver.sh, aber mit den selbst gebauten Dateien statt
# der Release-Dateien von GitHub
SVWS_APP_PATH="/opt/app/svws"
SVWS_CONF_PATH="/etc/app/svws/conf"
# Der Linux-Installer legt die svwsconfig.json im Programmverzeichnis ab
SVWS_CONFIG="${SVWS_APP_PATH}/svwsconfig.json"
ENV_FILE="${SCRIPTS_DIR}/.env"

INSTALL_SCRIPT=$(printf '%s\n' "$LINUX_DIST_DIR"/install-*.sh | sort -V | tail -n 1)
INSTALL_ARCHIVE=$(printf '%s\n' "$LINUX_DIST_DIR"/linux-installer-*.tar.gz | sort -V | tail -n 1)
if [ -z "$INSTALL_SCRIPT" ] || [ -z "$INSTALL_ARCHIVE" ]; then
    echo "Fehler: Installer (install-*.sh / linux-installer-*.tar.gz) in ${LINUX_DIST_DIR} nicht gefunden."
    exit 1
fi

# Antworten für den Installer. Die Datei dient zugleich als .env für
# create_svws_testdbs.sh und delete_all_svws_dbs.sh (MARIADB_ROOT_PASSWORD)
cat > "$ENV_FILE" <<EOF
CREATE_MARIADB=j
CREATE_KEYSTORE=j
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
APP_PATH=${SVWS_APP_PATH}
CONF_PATH=${SVWS_CONF_PATH}
APP_PORT=8443
SVWS_TLS_KEYSTORE_PATH=${SVWS_CONF_PATH}/keystore
SVWS_TLS_KEYSTORE_PASSWORD=${MARIADB_ROOT_PASSWORD}
SVWS_TLS_KEY_ALIAS=svws
INPUT_COMMON_NAME=svws
INPUT_ORGANIZATIONAL_UNIT=svws
INPUT_ORGANIZATION=svws
INPUT_LOCALITY=NRW
INPUT_STATE=NRW
INPUT_COUNTRY=DE
validity_days=3650
EOF
chmod 600 "$ENV_FILE"

# Installer in einem eigenen Arbeitsordner ausführen: er erwartet .env und
# das Archiv im aktuellen Verzeichnis
INSTALL_WORK_DIR=$(mktemp -d)
cp "$INSTALL_SCRIPT" "$INSTALL_ARCHIVE" "$ENV_FILE" "$INSTALL_WORK_DIR"/
echo "Installiere $(basename "$INSTALL_ARCHIVE") mit $(basename "$INSTALL_SCRIPT")..."
if ! ( cd "$INSTALL_WORK_DIR" && bash "./$(basename "$INSTALL_SCRIPT")" ); then
    rm -rf "$INSTALL_WORK_DIR"
    echo "Fehler: Die Installation des SVWS-Servers ist fehlgeschlagen."
    exit 1
fi
rm -rf "$INSTALL_WORK_DIR"

# ServerMode aus -m setzen (der Installer richtet den Standard ein)
if [ -f "$SVWS_CONFIG" ]; then
    sed -i 's|"ServerMode"[[:space:]]*:[[:space:]]*"[^"]*"|"ServerMode" : "'"${SERVERMODE}"'"|' "$SVWS_CONFIG"
    systemctl restart svws
else
    echo "Hinweis: ${SVWS_CONFIG} nicht gefunden, ServerMode wurde nicht gesetzt."
fi

#############################################
# 5. WeNoM installieren (Apache2, nur Port 443)
# Vor der WebLuPO, damit Port 80 bei der Apache-Installation noch frei ist
#############################################
echo "Starte install_wenom_testserver.sh (Version: $SVWSVERSION)..."
WENOM_ARGS=(-v "$SVWSVERSION")
[ -n "$DOMAIN" ] && WENOM_ARGS+=(-d "$DOMAIN")
if ! bash "${SCRIPTS_DIR}/install_wenom_testserver.sh" "${WENOM_ARGS[@]}"; then
    echo "Fehler: install_wenom_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 6. WebLuPO installieren (nginx, Port 80, unter /weblupo/)
#############################################
echo "Starte install_weblupo_testserver.sh (Version: $SVWSVERSION)..."
if ! bash "${SCRIPTS_DIR}/install_weblupo_testserver.sh" -v "$SVWSVERSION"; then
    echo "Fehler: install_weblupo_testserver.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 7. Selbst gebaute WeNoM- und WebLuPO-Version einspielen
#############################################
# Die Installationsskripte richten Apache und nginx mit einer Release-Version ein.
# Damit WeNoM und WebLuPO zum gebauten SVWS-Server passen, werden sie mit den
# Dateien aus dem eigenen Build überschrieben (die WeNoM-Datenbank bleibt erhalten).
WENOM_ZIP=$(printf '%s\n' "$WENOM_BUILD_DIR"/WeNoM-*.zip | sort -V | tail -n 1)
WEBLUPO_ZIP=$(printf '%s\n' "$WEBLUPO_BUILD_DIR"/SVWS-Laufbahnplanung-*.zip | sort -V | tail -n 1)

if [ -n "$WENOM_ZIP" ]; then
    echo "Spiele $(basename "$WENOM_ZIP") ein..."
    unzip -q -o "$WENOM_ZIP" -d /var/www/html/wenom
    chown -R www-data:www-data /var/www/html/wenom
    systemctl restart 'php*-fpm.service'
else
    echo "Hinweis: Kein gebautes WeNoM gefunden, die Release-Version bleibt installiert."
fi

if [ -n "$WEBLUPO_ZIP" ]; then
    echo "Spiele $(basename "$WEBLUPO_ZIP") ein..."
    unzip -q -o "$WEBLUPO_ZIP" -d /var/www/html/weblupo
    chown -R www-data:www-data /var/www/html/weblupo
else
    echo "Hinweis: Keine gebaute WebLuPO gefunden, die Release-Version bleibt installiert."
fi

#############################################
# 8. SVWS-Tools installieren
#############################################
TOOLS_DIR="${SVWS_APP_PATH}/tools"
TOOLS_URL="https://github.com/SVWS-NRW/SVWS-Tools/releases/download/v${SVWSVERSION}/svws-tools-${SVWSVERSION}.zip"

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
chown -R --reference="$SVWS_APP_PATH" "$TOOLS_DIR"

# SVWS-Server auf die Tools hinweisen (AppsPath) und neu starten
if [ -f "$SVWS_CONFIG" ] && grep -q '"AppsPath"' "$SVWS_CONFIG"; then
    sed -i 's|"AppsPath"[[:space:]]*:[[:space:]]*[^,]*|"AppsPath" : "'"$TOOLS_DIR"'"|' "$SVWS_CONFIG"
    echo "AppsPath in ${SVWS_CONFIG} gesetzt: $(grep '"AppsPath"' "$SVWS_CONFIG" | sed 's/^[[:space:]]*//')"
else
    echo "Fehler: ${SVWS_CONFIG} fehlt oder enthält keinen Eintrag AppsPath."
    exit 1
fi
systemctl restart svws

#############################################
# 9. Übersichtsseite /var/www/html/index.html erzeugen
#############################################
INDEX_FILE="/var/www/html/index.html"

# Tabellenzeilen für alle Dateien im Download-Verzeichnis erzeugen
DOWNLOAD_ROWS=""
while IFS= read -r FILE; do
    DOWNLOAD_ROWS+="                <tr>
                    <td><a href=\"download/${FILE}\">${FILE}</a></td>
                </tr>
"
done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
if [ -z "$DOWNLOAD_ROWS" ]; then
    DOWNLOAD_ROWS="                <tr>
                    <td>Keine Build-Dateien vorhanden</td>
                </tr>
"
fi

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
        <p><b>BUILD ${BUILD_DATE} - BRANCH ${BUILD_BRANCH} - SERVERMODE ${SERVERMODE}</b></p>
    </section>

    <section>
        <table class="w3-table w3-bordered w3-hoverable">
            <thead>
                <tr class="w3-light-grey">
                    <th>Download Files</th>
                </tr>
            </thead>
            <tbody>
${DOWNLOAD_ROWS}            </tbody>
        </table>
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
# 10. Testdatenbanken importieren
#############################################
# Eigenes Zufallspasswort für den Schema-Benutzer, wird am Ende angezeigt
SCHEMA_USER="svwsadmin"
SCHEMA_PASSWORD=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)

# Im Skriptordner ausführen: dort liegt die .env mit MARIADB_ROOT_PASSWORD
# (aus Schritt 4) und dorthin werden die
# Testdatenbanken (SVWS-TestSqlites) geladen
echo "Starte create_svws_testdbs.sh..."
if ! ( cd "$SCRIPTS_DIR" \
        && bash ./create_svws_testdbs.sh -u "$SCHEMA_USER" -p "$SCHEMA_PASSWORD" ); then
    echo "Fehler: create_svws_testdbs.sh wurde mit einem Fehler beendet."
    exit 1
fi

########################################################
# 11. Benutzerkennwörter in allen Testdatenbanken setzen
########################################################

# Ein gemeinsames neues Admin-Kennwort (12 bis 16 Zeichen) für alle Datenbanken
ADMIN_PW_LENGTH=$(( 12 + RANDOM % 5 ))
NEW_ADMIN_PW=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$ADMIN_PW_LENGTH")
PASSWORD_DIR="${SCRIPTS_DIR}/Kennwoerter"
mkdir -p "$PASSWORD_DIR"
chmod 700 "$PASSWORD_DIR"

# Datenbanken = die in Schritt 9 importierten SQLite-Dateien
TESTDB_FILES=( "${SCRIPTS_DIR}/SVWS-TestSqlites"/*.sqlite )
FAILED_DBS=()

for db_file in "${TESTDB_FILES[@]}"; do
    DB_NAME=$(basename "$db_file" .sqlite)
    echo "Setze Kennwörter in Datenbank ${DB_NAME}..."
    # Werte als Umgebungsvariablen übergeben; Admin hat in den Testdatenbanken
    # noch kein Kennwort, daher ist SVWS_ADMIN_PW leer
    if ! SCHEMA_NAME="$DB_NAME" \
         MARIADB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD" \
         SVWS_ADMIN="Admin" \
         SVWS_ADMIN_PW="" \
         OUTPUT_FILE="${PASSWORD_DIR}/Kennwoerter_${DB_NAME}.txt" \
         bash "${SCRIPTS_DIR}/generate_svws_userpasswords.sh" -np "$NEW_ADMIN_PW"; then
        FAILED_DBS+=("$DB_NAME")
    fi
done
chmod 600 "$PASSWORD_DIR"/*.txt 2>/dev/null || true

if [ ${#FAILED_DBS[@]} -gt 0 ]; then
    echo "Hinweis: In folgenden Datenbanken gab es Fehler beim Setzen der Kennwörter: ${FAILED_DBS[*]}"
fi

#############################################
# 12. Geschützten Testzugang /var/www/html/Testzugang einrichten (nur mit -a)
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

# Tabellenzeilen für alle Dateien erzeugen (MariaDB zuerst, dann die Kennwortlisten)
TESTZUGANG_ROWS=""
while IFS= read -r FILE; do
    TESTZUGANG_ROWS+="                <tr>
                    <td><a href=\"${FILE}\">${FILE}</a></td>
                </tr>
"
done < <(find "$TESTZUGANG_DIR" -maxdepth 1 -type f -name '*.txt' -printf '%f\n' \
         | sort | awk '$0=="MariaDB.txt"{print; next} {rest=rest $0 "\n"} END{printf "%s", rest}')

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
        <p>Zugangsdaten für diesen Testserver – <b>nur für Test- und Schulungszwecke</b>.</p>
        <p>Der Benutzer <b>Admin</b> hat in allen Testdatenbanken dasselbe Kennwort
        (siehe Kennwortlisten).</p>
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


#############################################
# Abschluss
#############################################
echo "------------------------------------------------"
echo "Installation abgeschlossen."
if [ "$PW_WAS_GENERATED" = true ]; then
    echo "WICHTIG: Das generierte MariaDB-Root-Passwort lautet: $MARIADB_ROOT_PASSWORD"
fi
echo "Das MariaDB-Root-Passwort ist gespeichert in: $ENV_FILE (nur für root lesbar)"
echo "Testdatenbanken: Benutzer '$SCHEMA_USER', Passwort: $SCHEMA_PASSWORD"
echo "SVWS-Benutzer 'Admin' in allen Testdatenbanken, Passwort: $NEW_ADMIN_PW"
echo "Kennwörter aller übrigen Benutzer: ${PASSWORD_DIR}/Kennwoerter_<Datenbank>.txt"
echo "Übersichtsseite: http://${SERVER_HOST}/"
if [ -n "$ACCESS_PASSWORD" ]; then
    echo "Testzugang (Kennwörter): http://${SERVER_HOST}/Testzugang/ - Benutzer ${TESTZUGANG_USER}, Passwort aus -a"
fi
echo "Protokoll der Installation: $LOG_FILE"
echo "------------------------------------------------"

