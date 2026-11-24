#!/bin/bash
##############################################################################
# Setzt zufällige Kennwörter für alle Benutzer einer SVWS-Datenbank
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
Verwendung: bash $(basename "$0") [-np <Neues Admin-Passwort>]

Setzt für alle Benutzer einer SVWS-Datenbank außer Admin ein zufälliges Kennwort
und schreibt die Liste in die Datei Kennwoerter.txt.
Vor dem Aufruf oben im Skript eintragen oder als Umgebungsvariablen übergeben:
SERVERNAME, APP_PORT, SCHEMA_NAME, MARIADB_ROOT_PASSWORD, SVWS_ADMIN,
SVWS_ADMIN_PW (darf leer sein) und optional OUTPUT_FILE (Standard: Kennwoerter.txt).

Optionen:
  -np  Neues Kennwort für den Benutzer Admin. Wird zum Schluss gesetzt,
       nachdem alle anderen Benutzer ein neues Kennwort erhalten haben.
       Ohne -np bleibt das Kennwort von Admin unverändert.
  -h   Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0") -np NeuesAdminKennwort
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

# --- Konfiguration ---
# Die Werte können als Umgebungsvariablen übergeben werden (z. B. vom
# All-in-one-Skript). Sind sie nicht gesetzt, gelten die Werte hier:
SERVERNAME="${SERVERNAME:-localhost}"
APP_PORT="${APP_PORT:-8443}"
SCHEMA_NAME="${SCHEMA_NAME:-}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
SVWS_ADMIN="${SVWS_ADMIN:-}"
SVWS_ADMIN_PW="${SVWS_ADMIN_PW:-}"      # darf leer sein (z. B. Admin ohne Kennwort)
OUTPUT_FILE="${OUTPUT_FILE:-Kennwoerter.txt}"

# Parameter auswerten (-np besteht aus zwei Buchstaben, daher ohne getopts)
NEW_ADMIN_PW=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -np)
            if [ -z "${2:-}" ]; then
                echo "Fehler: -np braucht ein Kennwort."
                usage
            fi
            NEW_ADMIN_PW="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$SCHEMA_NAME" ] || [ -z "$SVWS_ADMIN" ]; then
    echo "Fehler: SCHEMA_NAME und SVWS_ADMIN müssen gesetzt sein (oben im Skript oder als Umgebungsvariablen)."
    usage
fi

# Falls die Datei existiert, leeren wir sie für einen sauberen Durchlauf
> "$OUTPUT_FILE"

echo "Starte Passwort-Update für Schema: ${SCHEMA_NAME}..."

# Erstellen einer temporäre Konfigurationsdatei
CONF_FILE=$(mktemp)
# Temporäre Datei mit dem Root-Passwort beim Beenden des Skripts immer löschen
trap 'rm -f "$CONF_FILE"' EXIT
cat << EOF > "$CONF_FILE"
[client]
user=root
password="${MARIADB_ROOT_PASSWORD}"
host=localhost
EOF

# Sicherstellen, dass nur der aktuelle User die Datei lesen kann
chmod 600 "$CONF_FILE"

echo "Starte Passwort-Update für Schema: ${SCHEMA_NAME}..."

# Auslesen der User
USERS=$(mysql --defaults-extra-file="$CONF_FILE" -N -s -e "SELECT ID, Benutzername FROM ${SCHEMA_NAME}.Credentials WHERE Benutzername != 'Admin';")

# Prüfen ob der Befehl geklappt hat
if [ $? -ne 0 ]; then
    echo "[FEHLER] Datenbank-Zugriff verweigert. Prüfe das Passwort."
    rm -f "$CONF_FILE"
    exit 1
fi

# Falls keine User gefunden wurden
if [ -z "$USERS" ]; then
    echo "Keine passenden Benutzer gefunden."
    # Ohne -np gibt es nichts mehr zu tun
    [ -z "$NEW_ADMIN_PW" ] && exit 0
fi

# Schleife über alle gefundenen User
echo "$USERS" | while read -r ID USERNAME; do
    # leere Zeile (keine Benutzer gefunden) überspringen
    [ -z "$ID" ] && continue

    # Passwort generieren (12 Zeichen, Alphanumerisch)
    PASSWORD=$(openssl rand -base64 12)

    # 3) In Datei schreiben
    echo "User: $USERNAME | Passwort: $PASSWORD" >> "$OUTPUT_FILE"


# Curl-Befehl zum Passwort setzen
CURL_COMMAND="curl --user \"${SVWS_ADMIN}:${SVWS_ADMIN_PW}\" -k -s -o /dev/null -w \"%{http_code}\" -X POST \
      \"https://${SERVERNAME}:${APP_PORT}/db/${SCHEMA_NAME}/benutzer/${ID}/password\" \
      -H \"accept: */*\" \
      -H 'Content-Type: application/json' \
      -d \"\\\"${PASSWORD}\\\"\""

# Optional: Den Befehl auf der Konsole anzeigen
#echo "Führe aus: $CURL_COMMAND"

# Passwort setzen
HTTP_CODE=$(eval $CURL_COMMAND)

    if [[ "$HTTP_CODE" =~ ^20[0-4]$ ]]; then
        echo -e "[OK] ID ${ID} ($USERNAME): Password erfolgreich gesetzt (Status: $HTTP_CODE).\n"
    else
        echo -e "[FEHLER] ID ${ID} ($USERNAME): Fehlgeschlagen (Status: $HTTP_CODE).\n"
    fi

done

echo "Alle Passwörter außer für \"Admin\" gesetzt. Die Passwörter wurden in $OUTPUT_FILE gespeichert."

# Optional (-np): neues Kennwort für Admin ganz zum Schluss setzen,
# weil die Anmeldung danach evtl. nicht mehr mit dem alten Kennwort klappt
if [ -n "$NEW_ADMIN_PW" ]; then
    ADMIN_ID=$(mysql --defaults-extra-file="$CONF_FILE" -N -s -e "SELECT ID FROM ${SCHEMA_NAME}.Credentials WHERE Benutzername = 'Admin';")
    if [ -z "$ADMIN_ID" ]; then
        echo "[FEHLER] Der Benutzer Admin wurde in ${SCHEMA_NAME} nicht gefunden."
        exit 1
    fi

    # Kennwort als JSON-String übergeben (Anführungszeichen und Backslashes maskieren)
    JSON_PW=$(printf '%s' "$NEW_ADMIN_PW" | sed 's/\\/\\\\/g; s/"/\\"/g')
    HTTP_CODE=$(curl --user "${SVWS_ADMIN}:${SVWS_ADMIN_PW}" -k -s -o /dev/null -w "%{http_code}" -X POST \
        "https://${SERVERNAME}:${APP_PORT}/db/${SCHEMA_NAME}/benutzer/${ADMIN_ID}/password" \
        -H "accept: */*" \
        -H "Content-Type: application/json" \
        -d "\"${JSON_PW}\"")

    if [[ "$HTTP_CODE" =~ ^20[0-4]$ ]]; then
        echo "User: Admin | Passwort: $NEW_ADMIN_PW" >> "$OUTPUT_FILE"
        echo "[OK] ID ${ADMIN_ID} (Admin): Neues Kennwort gesetzt (Status: $HTTP_CODE)."
    else
        echo "[FEHLER] ID ${ADMIN_ID} (Admin): Kennwort konnte nicht gesetzt werden (Status: $HTTP_CODE)."
        exit 1
    fi
fi
