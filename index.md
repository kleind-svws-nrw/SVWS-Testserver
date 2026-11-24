# Installationsskripte für Test- und Schulungsserver

Diese Sammlung enthält Bash-Skripte, mit denen sich Test- und Schulungsserver rund um den SVWS-Server schnell aufsetzen, befüllen und aktualisieren lassen:

+ SVWS-Server über den offiziellen Linux-Installer
+ SVWS-Server direkt aus einem GitHub-Branch gebaut
+ WeNoM (auch als Multi-Instanz) und WebLuPO
+ Hilfsskripte zum Anlegen, Klonen und Löschen von Datenbanken sowie zum Setzen von Benutzerkennwörtern

> **Hinweis:** Die Skripte sind für **Test- und Schulungszwecke** gedacht, nicht für den Produktivbetrieb. Sie arbeiten mit selbstsignierten Zertifikaten, teils weit geöffneten Dateirechten und geben Kennwörter auf der Konsole aus.

## Voraussetzungen

+ Alle Skripte sind mit **Debian 13** getestet und laufen auf einer einfachen Basisinstallation durch.
+ Die Skripte werden als **root** ausgeführt (sie installieren Pakete, legen Dienste an und ändern Systemeinstellungen).
+ Die Installationsskripte setzen die Systemsprache auf `de_DE.UTF-8` und die Zeitzone auf `Europe/Berlin` und führen ein vollständiges `apt upgrade` aus.
+ Jedes Skript zeigt mit `-h` (oder `--help`) eine Hilfe mit allen Optionen und einem Beispiel an, ohne am System etwas zu verändern.
+ Versionsnummern werden ohne führendes `v` angegeben, also z. B. `1.3.2`. Die passenden Versionen stehen unter [SVWS-Server Releases](https://github.com/SVWS-NRW/SVWS-Server/releases).

## Übersicht

| Skript | Zweck |
|-|-|
| [download_all_scripts.sh](#download_all_scriptssh) | Lädt alle Skripte dieser Sammlung herunter |
| [install_svws_testserver_linuxinstaller.sh](#install_svws_testserver_linuxinstallersh) | SVWS-Server mit dem offiziellen Linux-Installer |
| [install_svws_testserver_fromScratch.sh](#install_svws_testserver_fromscratchsh) | SVWS-Server aus einem GitHub-Branch bauen |
| [update_testserver_from_scratch.sh](#update_testserver_from_scratchsh) | Aus dem Branch gebauten SVWS-Server aktualisieren |
| [install_wenom_testserver.sh](#install_wenom_testserversh) | WeNoM unter Apache2 einrichten |
| [update_wenom_testserver.sh](#update_wenom_testserversh) | WeNoM neu einspielen |
| [wenom_to_multiwenom.sh](#wenom_to_multiwenomsh) | Mehrere WeNoM-Instanzen über eigene Subdomains |
| [install_weblupo_testserver.sh](#install_weblupo_testserversh) | WebLuPO unter nginx einrichten |
| [create_svws_testdbs.sh](#create_svws_testdbssh) | Test-Datenbanken (SQLite) in den SVWS-Server importieren |
| [clone_db.sh](#clone_dbsh) | Eine Datenbank n-mal klonen |
| [delete_all_svws_dbs.sh](#delete_all_svws_dbssh) | Alle Datenbanken des SVWS-Servers löschen |
| [generate_svws_userpasswords.sh](#generate_svws_userpasswordssh) | Zufällige Kennwörter für alle Benutzer einer Datenbank setzen |

---

## Skripte herunterladen

### download_all_scripts.sh

Lädt alle Skripte dieser Sammlung über die GitHub-API in den neu angelegten Unterordner `Installationsskripte` herunter. Vorab werden das System aktualisiert und `curl` sowie `jq` installiert.

**Beispiel:**

```bash
wget https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/download_all_scripts.sh
bash download_all_scripts.sh
cd Installationsskripte
```

**Download** -> [download_all_scripts.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/download_all_scripts.sh)

---

## SVWS-Server installieren

### install_svws_testserver_linuxinstaller.sh

Installiert den SVWS-Server mit dem auf GitHub veröffentlichten Linux-Installer. Das Skript lädt Installer und Server-Paket der angegebenen Version herunter und schreibt vorab alle Antworten in eine `.env`-Datei, sodass die Installation ohne Rückfragen durchläuft.

Ergebnis:

+ lokale MariaDB, Root-Passwort = angegebenes Passwort
+ SVWS-Server unter `/opt/app/svws`, Konfiguration unter `/etc/app/svws/conf`
+ Keystore mit demselben Passwort, Port `8443`

**Optionen:**

| Parameter | Info |
|-|-|
| -v | Pflicht: Version des SVWS-Servers |
| -p | Pflicht: Passwort für MariaDB-Root und Keystore |

**Beispiel:**

```bash
bash install_svws_testserver_linuxinstaller.sh -v 1.3.2 -p svwsadmin
```

Der SVWS-Server ist danach unter `https://<Server-IP>:8443` erreichbar.

**Download** -> [install_svws_testserver_linuxinstaller.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/install_svws_testserver_linuxinstaller.sh)

### install_svws_testserver_fromScratch.sh

Baut den SVWS-Server direkt aus den Quellen eines GitHub-Branches, z. B. um den aktuellen Entwicklungsstand zu testen.

Das Skript:

+ installiert MariaDB und Java (Temurin 21)
+ legt den Benutzer `svws` an
+ klont das Repository nach `/app/SVWS-Server` und baut es mit Gradle (ohne Tests)
+ erzeugt Keystore und `svwsconfig.json` (Port `8443`)
+ richtet den systemd-Dienst `svws` ein und startet ihn

**Optionen:**

| Parameter | Info |
|-|-|
| -m | Optional: ServerMode, der in die `svwsconfig.json` eingetragen wird, z. B. `stable`. Ohne Angabe wird `dev` verwendet. |
| -b | Optional: Git-Branch, z. B. `master`. Ohne Angabe wird `dev` verwendet. |
| -p | Optional: Passwort für MariaDB-Root. Ohne Angabe wird ein Passwort erzeugt und am Ende angezeigt. |

**Beispiel:**

```bash
bash install_svws_testserver_fromScratch.sh -p svwsadmin                    # Branch und ServerMode dev (Standard)
bash install_svws_testserver_fromScratch.sh -m stable -b master -p svwsadmin
```

Der Dienst lässt sich mit `systemctl status svws` prüfen.

**Download** -> [install_svws_testserver_fromScratch.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/install_svws_testserver_fromScratch.sh)

### update_testserver_from_scratch.sh

Aktualisiert einen mit `install_svws_testserver_fromScratch.sh` installierten Server: Dienst stoppen, lokale Änderungen in `/app/SVWS-Server` verwerfen, `git pull`, mit Gradle neu bauen (`clean`, `wipe`, `assemble`) und Dienst wieder starten. Der Verlauf wird in `~/svws-update.log` protokolliert.

Das Skript hat außer `-h` keine Parameter und eignet sich z. B. für einen nächtlichen Cronjob.

**Beispiel:**

```bash
bash update_testserver_from_scratch.sh
```

**Download** -> [update_testserver_from_scratch.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/update_testserver_from_scratch.sh)

---

## WeNoM und WebLuPO

### install_wenom_testserver.sh

Installiert Apache2 mit PHP 8.4 und richtet den WeNoM unter `/var/www/html/wenom` ein:

+ Apache lauscht nur auf HTTPS (Port 443): `Listen 80` wird in der `/etc/apache2/ports.conf` auskommentiert und die Standard-Site `000-default` gelöscht. Port 80 ist damit frei, z. B. für einen anderen Webserver.
+ ein selbstsigniertes Zertifikat (10 Jahre gültig) wird erzeugt, mit Domain und IP oder nur mit der IP
+ `mod_security2` wird aktiviert
+ zum Schluss wird das Client-Secret für die Synchronisation mit dem SVWS-Server erzeugt und angezeigt

**Optionen:**

| Parameter | Info |
|-|-|
| -v | Pflicht: Version des SVWS-Servers (WeNoM wird passend dazu geladen) |
| -d | Optional: Domainname für Zertifikat und VirtualHost, ohne Angabe wird nur die IP verwendet |

**Beispiel:**

```bash
bash install_wenom_testserver.sh -v 1.3.3 -d wenom.meineschule.de
```

**Download** -> [install_wenom_testserver.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/install_wenom_testserver.sh)

### update_wenom_testserver.sh

Spielt den WeNoM unter `/var/www/html/wenom` neu ein, setzt die Rechte, erzeugt ein neues Client-Secret und zeigt es an.

> **Achtung:** Das Update löscht die bestehende Installation einschließlich aller WeNoM-Datenbankeinträge. Vorher ein Backup anlegen. Im Skript steht dafür eine auskommentierte Zeile bereit.

Optional kann das Secret zu Testzwecken unter `https://<Server>/secret/secret.html` veröffentlicht werden (auskommentierter Block im Skript).

**Optionen:**

| Parameter | Info |
|-|-|
| -v | Pflicht: Version des SVWS-Servers (WeNoM wird passend dazu geladen) |
| -y | Optional: ohne Sicherheitsabfrage ausführen |

**Beispiel:**

```bash
bash update_wenom_testserver.sh -v 1.3.3 -y
```

**Download** -> [update_wenom_testserver.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/update_wenom_testserver.sh)

### wenom_to_multiwenom.sh

Macht aus einer WeNoM-Installation mehrere voneinander getrennte Instanzen, z. B. eine pro Schulungsteilnehmer. Für jede Instanz `i` werden angelegt:

+ ein eigener Datenbankordner `/var/www/html/db/wenom<i>`
+ ein Apache-VirtualHost `wenom<i>.<Domain>` auf Port 443, der über `ENM_DB_DIR` auf diesen Ordner zeigt

Danach wird Apache neu geladen.

Voraussetzungen:

+ Für jede Subdomain (`wenom1.<Domain>`, `wenom2.<Domain>`, …) muss ein DNS-Eintrag auf den Server zeigen.
+ Das Skript erwartet die WeNoM-Dateien unter `/var/www/html/public` und das Zertifikat aus `install_wenom_testserver.sh`. Abweichende Pfade werden oben im Skript angepasst (`DB_FOLDER`, `WEBROOT`, `SSL_CERT`, `SSL_KEY`).

**Optionen:**

| Parameter | Info |
|-|-|
| -n | Pflicht: Anzahl der Instanzen |
| -url | Pflicht: Domain, an die `wenom<i>.` vorangestellt wird |

**Beispiel:**

```bash
bash wenom_to_multiwenom.sh -n 15 -url meineschule.de
```

Erzeugt `wenom1.meineschule.de` bis `wenom15.meineschule.de`.

**Download** -> [wenom_to_multiwenom.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/wenom_to_multiwenom.sh)

### install_weblupo_testserver.sh

Installiert nginx und richtet die WebLuPO (Laufbahnplanung) der angegebenen Version unter `/var/www/html/weblupo` ein. nginx liefert sie als Standard-Site auf Port 80 aus; die mitgelieferte nginx-Standard-Site wird dabei entfernt.

Ist Port 80 bereits durch einen anderen Dienst belegt, bricht das Skript mit einem Hinweis ab. Zusammen mit `install_wenom_testserver.sh` auf einem Server funktioniert es, weil Apache dort nur auf Port 443 lauscht.

**Optionen:**

| Parameter | Info |
|-|-|
| -v | Pflicht: Version des SVWS-Servers (WebLuPO wird passend dazu geladen) |

**Beispiel:**

```bash
bash install_weblupo_testserver.sh -v 1.3.2
```

Die WebLuPO ist danach unter `http://<Server-IP>` erreichbar.

**Download** -> [install_weblupo_testserver.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/install_weblupo_testserver.sh)

---

## Datenbanken verwalten

### create_svws_testdbs.sh

Importiert SQLite-Testdatenbanken über die API in einen laufenden SVWS-Server (`https://localhost:8443`). Jede Datei wird als eigenes Schema angelegt; der Schemaname ist der Dateiname ohne `.sqlite`.

+ Ohne `-d` wird das Repository [SVWS-NRW/SVWS-TestSqlites](https://github.com/SVWS-NRW/SVWS-TestSqlites) in den Ordner `SVWS-TestSqlites` geklont bzw. aktualisiert, und alle enthaltenen `.sqlite`-Dateien werden importiert.
+ Mit `-d` wird nur die angegebene Datei heruntergeladen und importiert.

Das MariaDB-Root-Passwort wird aus der Zeile `MARIADB_ROOT_PASSWORD=` einer `.env`-Datei im selben Ordner wie das Skript gelesen. Diese Datei muss vorhanden sein.

**Optionen:**

| Parameter | Info |
|-|-|
| -u | Optional: Benutzername für die neuen Schemata, Standard `svwsadmin` |
| -p | Optional: Passwort dieses Benutzers, Standard `svwsadmin` |
| -d | Optional: URL einer einzelnen `.sqlite`-Datei |

**Beispiele:**

```bash
# alle Testdatenbanken aus dem Repository importieren
bash create_svws_testdbs.sh -u svwsadmin -p geheim

# eine einzelne Datenbank importieren
bash create_svws_testdbs.sh -d https://github.com/SVWS-NRW/SVWS-TestMDBs/raw/refs/heads/main/Grundschule/Grundschule_JB-2025.sqlite
```

**Download** -> [create_svws_testdbs.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/create_svws_testdbs.sh)

### clone_db.sh

Klont eine vorhandene Datenbank des SVWS-Servers n-mal, z. B. um jedem Schulungsteilnehmer eine eigene Kopie zu geben. Die Klone heißen `<Name>_1` bis `<Name>_n`.

Das Skript:

+ erstellt einen Dump der Quelldatenbank und spielt ihn in jeden Klon ein
+ gibt dem Datenbankbenutzer der Quelle Rechte auf die Klone
+ trägt die Klone mit denselben Zugangsdaten in die `svwsconfig.json` ein
+ startet den Dienst `svws` neu

Voraussetzungen:

+ Der Server wurde mit dem Linux-Installer installiert (systemd-Dienst `svws`).
+ Die `svwsconfig.json` liegt unter `/opt/app/svws/conf`, `/opt/app/svws` oder `/etc/svws`.
+ `jq` ist installiert.

**Optionen:**

| Parameter | Info |
|-|-|
| -d | Pflicht: Name der vorhandenen Datenbank (Schema) |
| -n | Pflicht: Anzahl der Klone |
| -p | Optional: MariaDB-Root-Passwort. Ohne Angabe wird `MARIADB_ROOT_PASSWORD` aus einer `.env` im aktuellen Verzeichnis gelesen. |

**Beispiel:**

```bash
bash clone_db.sh -d svwsdb -n 15 -p svwsadmin
```

**Download** -> [clone_db.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/clone_db.sh)

### delete_all_svws_dbs.sh

Löscht **alle** Datenbanken (Schemata) eines SVWS-Servers über die API, z. B. um einen Schulungsserver zurückzusetzen. Vorher fragt das Skript nach einer Bestätigung. Jeder Schritt wird in `svws-delete.log` protokolliert. Fehlt `jq`, wird es installiert.

Liegt neben dem Skript eine `.env`-Datei, werden die Werte daraus übernommen (z. B. `MARIADB_ROOT_PASSWORD`, `APP_PORT`). Parameter haben Vorrang. Ohne `.env` wird Port `8443` verwendet.

**Optionen:**

| Parameter | Info |
|-|-|
| -p | Optional: MariaDB-Root-Passwort (Pflicht, wenn keine `.env` vorhanden ist) |
| -s | Optional: Servername, Standard `localhost` |
| -Y | Optional: ohne Sicherheitsabfrage löschen |
| -h | Hilfe anzeigen |

**Beispiel:**

```bash
bash delete_all_svws_dbs.sh -p svwsadmin
```

**Download** -> [delete_all_svws_dbs.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/delete_all_svws_dbs.sh)

### generate_svws_userpasswords.sh

Setzt für alle Benutzer einer SVWS-Datenbank außer `Admin` ein zufälliges Kennwort und schreibt die Liste `Benutzer | Passwort` in die Datei `Kennwoerter.txt`. Das ist praktisch, um Schulungsteilnehmern eigene Zugänge zu geben.

Das Skript hat außer `-h` keine Parameter. Die Werte werden vor dem Aufruf oben im Skript eingetragen:

| Variable | Info |
|-|-|
| SERVERNAME | Servername, Standard `localhost` |
| APP_PORT | Port des SVWS-Servers, Standard `8443` |
| SCHEMA_NAME | Name der Datenbank |
| MARIADB_ROOT_PASSWORD | MariaDB-Root-Passwort (zum Auslesen der Benutzer) |
| SVWS_ADMIN | Benutzer mit Adminrechten in der Datenbank |
| SVWS_ADMIN_PW | Kennwort dieses Benutzers |

Voraussetzung ist ein MariaDB/MySQL-Client auf dem Server.

**Beispiel:**

```bash
bash generate_svws_userpasswords.sh
cat Kennwoerter.txt
```

**Download** -> [generate_svws_userpasswords.sh](https://github.com/SVWS-NRW/Schulungsunterlagen/raw/refs/heads/master/Fachberatung_Anleitungen/Schulungsserver/Installationsskripte/generate_svws_userpasswords.sh)

---

## Typische Abläufe

**Schulungsserver mit eigener Datenbank für jeden Teilnehmer**

```bash
bash install_svws_testserver_linuxinstaller.sh -v 1.3.2 -p svwsadmin
bash create_svws_testdbs.sh -d <URL einer Testdatenbank>
bash clone_db.sh -d <Schemaname> -n 15 -p svwsadmin
```

`create_svws_testdbs.sh` braucht dafür eine `.env` mit `MARIADB_ROOT_PASSWORD=svwsadmin` im Skriptordner. Die `.env` des Linux-Installers aus dem ersten Schritt erfüllt das.

**Schulungsserver nach der Schulung zurücksetzen**

```bash
bash delete_all_svws_dbs.sh -p svwsadmin
bash create_svws_testdbs.sh
```
