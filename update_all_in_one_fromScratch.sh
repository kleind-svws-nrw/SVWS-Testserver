#!/bin/bash
##############################################################################
# Aktualisiert einen mit install_all_in_one_fromScratch.sh eingerichteten Testserver
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
Verwendung: bash $(basename "$0")

Aktualisiert einen mit install_all_in_one_fromScratch.sh eingerichteten
Testserver auf den aktuellen Stand seines Git-Branches:
  0. alte Build-Dateien löschen
  1. Quellen holen (git pull) und SVWS-Server, Linux-Installer, WeNoM und
     WebLuPO neu bauen (clean, wipe, build)
  2. alle Datenbanken des SVWS-Servers löschen
  3. WeNoM-Datenbank löschen
  4. SVWS-Server mit dem neuen Linux-Installer aktualisieren (--update)
  5. neues WeNoM einspielen und WeNoM-Datenbank neu einrichten
  6. neue WebLuPO einspielen
  7. Testdatenbanken neu importieren
  8. Benutzerkennwörter neu setzen (Admin-Kennwort aus der .env)
  9. Download-Bereich der Übersichtsseite aktualisieren
 10. Testzugang aktualisieren (Kennwortlisten, Admin-Kennwort, Links)

ACHTUNG: Alle Datenbanken und alle WeNoM-Daten werden gelöscht!
Erwartet die .env aus der Installation im Ordner dieses Skripts.

Optionen:
  -h  Diese Hilfe anzeigen (auch -help oder --help)

Beispiel:
  bash $(basename "$0")
EOF
    exit "${1:-1}"
}

for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "-help" || "$arg" == "--help" ]]; then
        usage 0
    fi
done
[ $# -gt 0 ] && usage

# --- Pfade (wie in install_all_in_one_fromScratch.sh) ---
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPTS_DIR}/.env"
SVWS_DIR="$(dirname "$SCRIPTS_DIR")/SVWS-Server"
LINUX_DIST_DIR="${SVWS_DIR}/deployment/linux-installer/build/distributions"
WENOM_BUILD_DIR="${SVWS_DIR}/svws-webclient/enmserver/build"
WEBLUPO_BUILD_DIR="${SVWS_DIR}/svws-webclient/laufbahnplanung/build"
SVWS_APP_PATH="/opt/app/svws"
SVWS_CONFIG="${SVWS_APP_PATH}/svwsconfig.json"
WENOM_DIR="/var/www/html/wenom"
WEBLUPO_DIR="/var/www/html/weblupo"
DOWNLOAD_DIR="/var/www/html/download"
INDEX_FILE="/var/www/html/index.html"
TESTZUGANG_DIR="/var/www/html/Testzugang"
PASSWORD_DIR="${SCRIPTS_DIR}/Kennwoerter"

# --- Gesamte Ausgabe zusätzlich in eine Logdatei schreiben ---
LOG_DIR="${SCRIPTS_DIR}/log"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
LOG_FILE="${LOG_DIR}/update_all_in_one_$(date '+%Y%m%d_%H%M%S').log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"    # enthält Kennwörter, daher nur für root lesbar
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Protokoll des Updates: $LOG_FILE"

export DEBIAN_FRONTEND=noninteractive
# Nicht passende Muster ergeben eine leere Liste statt des Musters selbst
shopt -s nullglob

# --- Voraussetzungen prüfen ---
for d in "${SVWS_DIR}/.git" "$SVWS_CONFIG" "$WENOM_DIR" "$WEBLUPO_DIR" "$ENV_FILE"; do
    if [ ! -e "$d" ]; then
        echo "Fehler: $d nicht gefunden. Wurde der Server mit install_all_in_one_fromScratch.sh eingerichtet?"
        exit 1
    fi
done

# Wert aus der .env lesen
env_value() {
    grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d '=' -f2- | tr -d '"' | tr -d "'"
}
MARIADB_ROOT_PASSWORD=$(env_value MARIADB_ROOT_PASSWORD)
TESTDB_ADMIN_PASSWORD=$(env_value TESTDB_ADMIN_PASSWORD)
SCHEMA_USER=$(env_value TESTDB_SCHEMA_USER)
SCHEMA_USER="${SCHEMA_USER:-svwsadmin}"
SCHEMA_PASSWORD=$(env_value TESTDB_SCHEMA_PASSWORD)

for key in MARIADB_ROOT_PASSWORD TESTDB_ADMIN_PASSWORD TESTDB_SCHEMA_PASSWORD; do
    if [ -z "$(env_value "$key")" ]; then
        echo "Fehler: ${key} fehlt in ${ENV_FILE}."
        if [ "$key" = "TESTDB_SCHEMA_PASSWORD" ]; then
            echo "Das Passwort des Schema-Benutzers steht in ${TESTZUGANG_DIR}/MariaDB.txt"
            echo "und kann als Zeile TESTDB_SCHEMA_PASSWORD=... in die .env eingetragen werden."
        fi
        exit 1
    fi
done

# Setzt einen Eintrag in der svwsconfig.json (legt ihn an, falls er fehlt)
set_svws_config() {
    local key="$1" value="$2" tmp
    tmp=$(mktemp)
    if jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$SVWS_CONFIG" > "$tmp"; then
        cat "$tmp" > "$SVWS_CONFIG"
        rm -f "$tmp"
        echo "${SVWS_CONFIG}: \"${key}\" : \"${value}\""
    else
        rm -f "$tmp"
        echo "Fehler: ${SVWS_CONFIG} konnte nicht gelesen werden."
        return 1
    fi
}

# Neueste Datei aus einer Liste
newest() { printf '%s\n' "$@" | sort -V | tail -n 1; }

# Ersetzt den Inhalt des ersten <tbody> einer HTML-Datei durch neue Zeilen
#   replace_first_tbody <Datei> <Zeilen>
replace_first_tbody() {
    local file="$1" rows="$2" tmp
    tmp=$(mktemp)
    if ROWS="$rows" awk '
        !done && /<tbody>/   { print; printf "%s", ENVIRON["ROWS"]; skip=1; next }
        skip && /<\/tbody>/  { skip=0; done=1 }
        !skip                { print }
        END { if (!done) exit 1 }
    ' "$file" > "$tmp"; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        echo "Fehler: In ${file} wurde keine Tabelle gefunden."
        return 1
    fi
}

# Eine Tabellenzeile mit Link
#   table_row <Link> <Text>
table_row() {
    printf '                <tr>\n                    <td><a href="%s">%s</a></td>\n                </tr>\n' "$1" "$2"
}

# Einstellungen merken, die das Installer-Update evtl. zurücksetzt
SERVERMODE=$(jq -r '.ServerMode // empty' "$SVWS_CONFIG")
APPS_PATH=$(jq -r '.AppsPath // empty' "$SVWS_CONFIG")

echo "Update des Basissystems..."
apt update && apt upgrade -y && apt autoremove -y

#############################################
# 0. Alte Build-Dateien löschen
#############################################
rm -f "${LINUX_DIST_DIR:?}"/install-* "${LINUX_DIST_DIR:?}"/linux-installer-* \
      "${WENOM_BUILD_DIR:?}"/WeNoM-* "${WEBLUPO_BUILD_DIR:?}"/SVWS-Laufbahnplanung-*

#############################################
# 1. Quellen holen und neu bauen
#############################################
BUILD_BRANCH=$(git -C "$SVWS_DIR" branch --show-current)
echo "Aktualisiere ${SVWS_DIR} (Branch: ${BUILD_BRANCH})..."
git -C "$SVWS_DIR" checkout -- .
if ! git -C "$SVWS_DIR" pull; then
    echo "Fehler: git pull ist fehlgeschlagen."
    exit 1
fi

if ! ( cd "$SVWS_DIR" \
        && ./gradlew clean wipe \
        && ./gradlew :svws-openapi:assembleTranspiled build -x test \
        && ./gradlew buildLinuxInstaller ); then
    echo "Fehler: Der Gradle-Build in ${SVWS_DIR} ist fehlgeschlagen."
    exit 1
fi
# todo: buildWindowsInstaller - variablen für gradle setzen

INSTALL_SCRIPT=$(newest "$LINUX_DIST_DIR"/install-*.sh)
INSTALL_ARCHIVE=$(newest "$LINUX_DIST_DIR"/linux-installer-*.tar.gz)
WENOM_ZIP=$(newest "$WENOM_BUILD_DIR"/WeNoM-*.zip)
WEBLUPO_ZIP=$(newest "$WEBLUPO_BUILD_DIR"/SVWS-Laufbahnplanung-*.zip)
for f in INSTALL_SCRIPT INSTALL_ARCHIVE WENOM_ZIP WEBLUPO_ZIP; do
    if [ -z "${!f}" ]; then
        echo "Fehler: Build-Datei für ${f} wurde nicht gefunden."
        exit 1
    fi
done

#############################################
# 2. Alle Datenbanken des SVWS-Servers löschen
#############################################
if ! bash "${SCRIPTS_DIR}/delete_all_svws_dbs.sh" -Y; then
    echo "Fehler: delete_all_svws_dbs.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 3. WeNoM-Datenbank löschen
#############################################
rm -f "${WENOM_DIR:?}/db/app.sqlite"

#############################################
# 4. SVWS-Server mit dem neuen Linux-Installer aktualisieren
#############################################
# Der Installer liest seine Antworten aus der .env im aktuellen Verzeichnis
INSTALL_WORK_DIR=$(mktemp -d)
cp "$INSTALL_SCRIPT" "$INSTALL_ARCHIVE" "$ENV_FILE" "$INSTALL_WORK_DIR"/
echo "Aktualisiere SVWS-Server mit $(basename "$INSTALL_SCRIPT") --update..."
if ! ( cd "$INSTALL_WORK_DIR" && bash "./$(basename "$INSTALL_SCRIPT")" --update ); then
    rm -rf "${INSTALL_WORK_DIR:?}"
    echo "Fehler: Das Update des SVWS-Servers ist fehlgeschlagen."
    exit 1
fi
rm -rf "${INSTALL_WORK_DIR:?}"

# ServerMode und AppsPath wiederherstellen, falls das Update sie zurückgesetzt hat
[ -n "$SERVERMODE" ] && set_svws_config "ServerMode" "$SERVERMODE"
[ -n "$APPS_PATH" ] && set_svws_config "AppsPath" "$APPS_PATH"
systemctl restart svws

#############################################
# 5. Neues WeNoM einspielen und Datenbank neu einrichten
#############################################
echo "Spiele $(basename "$WENOM_ZIP") ein..."
unzip -q -o "$WENOM_ZIP" -d "$WENOM_DIR"
chown -R www-data:www-data "$WENOM_DIR"
systemctl restart 'php*-fpm.service'
# Legt die WeNoM-Datenbank neu an (wie bei der Installation)
curl -k -s --request GET --url "https://localhost/api/setup" \
     --header "Content-Type: application/x-www-form-urlencoded" > /dev/null

#############################################
# 6. Neue WebLuPO einspielen
#############################################
echo "Spiele $(basename "$WEBLUPO_ZIP") ein..."
unzip -q -o "$WEBLUPO_ZIP" -d "$WEBLUPO_DIR"
chown -R www-data:www-data "$WEBLUPO_DIR"

#############################################
# 7. Testdatenbanken neu importieren
#############################################
# Warten, bis der SVWS-Server nach dem Neustart antwortet (max. 5 Minuten)
echo "Warte auf den SVWS-Server..."
for i in $(seq 1 60); do
    curl -k -s -o /dev/null "https://localhost:8443/" && break
    sleep 5
done

if ! ( cd "$SCRIPTS_DIR" \
        && bash ./create_svws_testdbs.sh -u "$SCHEMA_USER" -p "$SCHEMA_PASSWORD" ); then
    echo "Fehler: create_svws_testdbs.sh wurde mit einem Fehler beendet."
    exit 1
fi

#############################################
# 8. Benutzerkennwörter neu setzen
#############################################
mkdir -p "$PASSWORD_DIR"
chmod 700 "$PASSWORD_DIR"
rm -f "${PASSWORD_DIR:?}"/*

FAILED_DBS=()
for db_file in "${SCRIPTS_DIR}/SVWS-TestSqlites"/*.sqlite; do
    DB_NAME=$(basename "$db_file" .sqlite)
    echo "Setze Kennwörter in Datenbank ${DB_NAME}..."
    # Ohne -np nimmt das Skript TESTDB_ADMIN_PASSWORD aus der .env;
    # Admin hat in den frisch importierten Datenbanken noch kein Kennwort
    if ! SCHEMA_NAME="$DB_NAME" \
         MARIADB_ROOT_PASSWORD="$MARIADB_ROOT_PASSWORD" \
         SVWS_ADMIN="Admin" \
         SVWS_ADMIN_PW="" \
         OUTPUT_FILE="${PASSWORD_DIR}/Kennwoerter_${DB_NAME}.txt" \
         bash "${SCRIPTS_DIR}/generate_svws_userpasswords.sh"; then
        FAILED_DBS+=("$DB_NAME")
    fi
done
chmod 600 "$PASSWORD_DIR"/*.txt 2>/dev/null || true
if [ ${#FAILED_DBS[@]} -gt 0 ]; then
    echo "Hinweis: Fehler beim Setzen der Kennwörter in: ${FAILED_DBS[*]}"
fi

#############################################
# 9. Download-Bereich der Übersichtsseite aktualisieren
#############################################
mkdir -p "$DOWNLOAD_DIR"
rm -f "${DOWNLOAD_DIR:?}"/*
cp "$INSTALL_SCRIPT" "$INSTALL_ARCHIVE" "$WENOM_ZIP" "$WEBLUPO_ZIP" "$DOWNLOAD_DIR"/
chown www-data:www-data "$DOWNLOAD_DIR"/*

if [ -f "$INDEX_FILE" ]; then
    # Nur die erste Tabelle (Download Files) wird ersetzt,
    # die Tabelle mit den Links zu den Servern bleibt erhalten
    DOWNLOAD_ROWS=""
    while IFS= read -r f; do
        DOWNLOAD_ROWS+=$(table_row "download/${f}" "$f")$'\n'
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
    replace_first_tbody "$INDEX_FILE" "$DOWNLOAD_ROWS" || exit 1

    BUILD_DATE=$(date '+%Y-%m-%d %H:%M')
    sed -i "s|<p><b>BUILD .*</b></p>|<p><b>BUILD ${BUILD_DATE} - BRANCH ${BUILD_BRANCH} - SERVERMODE ${SERVERMODE}</b></p>|" "$INDEX_FILE"
    echo "Übersichtsseite aktualisiert: ${INDEX_FILE}"
else
    echo "Hinweis: ${INDEX_FILE} nicht gefunden, die Übersichtsseite wurde nicht aktualisiert."
fi

#############################################
# 10. Testzugang aktualisieren (nur wenn er eingerichtet ist)
#############################################
if [ -f "${TESTZUGANG_DIR}/index.html" ]; then
    # Kennwortlisten und WeNoM-Secret austauschen
    rm -f "${TESTZUGANG_DIR:?}"/Kennwoerter_*.txt
    cp "$PASSWORD_DIR"/Kennwoerter_*.txt "$TESTZUGANG_DIR"/ 2>/dev/null || true
    if [ -f "${WENOM_DIR}/db/client.sec" ]; then
        cat "${WENOM_DIR}/db/client.sec" > "${TESTZUGANG_DIR}/wenom_credential.txt"
    fi

    # Alle txt-Dateien verlinken: MariaDB und WeNoM zuerst, dann die Kennwortlisten
    TESTZUGANG_ROWS=""
    for f in MariaDB.txt wenom_credential.txt; do
        [ -f "${TESTZUGANG_DIR}/${f}" ] && TESTZUGANG_ROWS+=$(table_row "$f" "$f")$'\n'
    done
    while IFS= read -r f; do
        TESTZUGANG_ROWS+=$(table_row "$f" "$f")$'\n'
    done < <(find "$TESTZUGANG_DIR" -maxdepth 1 -type f -name '*.txt' \
                  ! -name MariaDB.txt ! -name wenom_credential.txt -printf '%f\n' | sort)
    replace_first_tbody "${TESTZUGANG_DIR}/index.html" "$TESTZUGANG_ROWS" || exit 1

    # Admin-Kennwort im Text aktualisieren
    sed -i "s|dasselbe Kennwort: <b>[^<]*</b>|dasselbe Kennwort: <b>${TESTDB_ADMIN_PASSWORD}</b>|" \
        "${TESTZUGANG_DIR}/index.html"

    chown -R www-data:www-data "$TESTZUGANG_DIR"
    find "$TESTZUGANG_DIR" -type f -exec chmod 644 {} +
    echo "Testzugang aktualisiert: ${TESTZUGANG_DIR}"
fi

echo "------------------------------------------------"
echo "Update abgeschlossen (Branch: ${BUILD_BRANCH})."
echo "SVWS-Benutzer 'Admin' in allen Testdatenbanken, Passwort: $TESTDB_ADMIN_PASSWORD"
echo "Protokoll des Updates: $LOG_FILE"
echo "------------------------------------------------"
