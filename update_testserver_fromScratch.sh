#!/bin/bash
##############################################################################
# Aktualisiert einen aus GitHub gebauten SVWS-Server
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

Aktualisiert einen aus GitHub gebauten SVWS-Server in /app/SVWS-Server
(git pull, Neubau mit Gradle, Neustart des Dienstes svws). Log: ~/svws-update.log

Optionen:
  -h  Diese Hilfe anzeigen

Beispiel:
  bash $(basename "$0")
EOF
    exit "${1:-1}"
}

# -h / --help auswerten, bevor am System etwas verändert wird
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage 0
    fi
done

# Configuration
APP_DIR="/app/SVWS-Server"
LOG_FILE="$HOME/svws-update.log"
SERVICE_NAME="svws"

echo "--- Update gestartet: $(date) ---" | tee -a "$LOG_FILE"


systemctl stop svws
cd $APP_DIR
chown -R svws:svws $APP_DIR
sudo -u svws git checkout -- .
sudo -u svws git pull | tee -a "$LOG_FILE"
sudo -u svws ./gradlew clean
sudo -u svws ./gradlew wipe
sudo -u svws ./gradlew assemble
systemctl start svws

systemctl -t service | grep $SERVICE_NAME >> "$LOG_FILE"
echo "--- Update beendet: $(date) ---" | tee -a "$LOG_FILE"