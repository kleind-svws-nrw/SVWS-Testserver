#!/bin/bash
APP_DIR="/app/SVWS-Server"
LOG_FILE="$HOME/svws-update.log"
DOWNLOAD_DIR="/var/www/html/download"
INDEX_FILE="/var/www/html/index.html"
TEMP_FILE=$(mktemp)

# Prüfen, ob Verzeichnis und Index-Datei existieren
if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo "Fehler: Download-Verzeichnis existiert nicht: $DOWNLOAD_DIR"
    exit 1
fi

if [ ! -f "$INDEX_FILE" ]; then
    echo "Fehler: index.html nicht gefunden: $INDEX_FILE"
    exit 1
fi

echo "update und upgrade des Basissystems ..."
apt update && apt upgrade -y && apt autoremove -y

# aufräumen
rm ${DOWNLOAD_DIR}/*
rm /app/SVWS-Server/deployment/linux-installer/build/distributions/install-*
rm /app/SVWS-Server/deployment/linux-installer/build/distributions/linux-installer-*
rm /app/SVWS-Server/svws-webclient/enmserver/build/WeNoM-*
rm /app/SVWS-Server/svws-webclient/laufbahnplanung/build/SVWS-Laufbahnplanung-*
#

echo "SVWS-Server update der Sources & rebuild ... "
systemctl stop svws
cd $APP_DIR
BRANCH=$(git branch --show-current)
echo "Working BRANCH:"
echo ${BRANCH}
#
chown -R root:root $APP_DIR
git checkout -- .
git pull | tee -a "$LOG_FILE"
./gradlew clean
./gradlew wipe
#./gradlew assemble
./gradlew build -x test
./gradlew buildLinuxInstaller

# todo: buildWindowsInstaller - variablen für gradle setzen
#./gradlew buildWindowsInstaller
chown -R svws:svws $APP_DIR
systemctl start svws


# Todo: index.html aufbauen