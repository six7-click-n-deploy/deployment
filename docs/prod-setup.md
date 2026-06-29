# Produktives Setup

Manuelle Anleitung, um den App-Store-Stack (10 Container — nginx,
frontend, backend, worker, keycloak + Postgres, postgres,
postgres-tfstate, rabbitmq, redis) auf einer einzelnen Ubuntu-VM
hochzuziehen. Alle Service-Images werden zur Laufzeit aus GHCR
gezogen — gebaut wird auf der VM nichts.

> [!TIP]
> Im CI-Betrieb läuft der Staging-Stack automatisch über
> `infrastructure/ansible/staging.yml`. Diese Anleitung beschreibt den
> manuellen Weg für eine isolierte Prod-Instanz auf einer eigenen VM,
> die du per IP erreichst.

## Voraussetzungen

| Werkzeug | Version | Anmerkung |
|---|---|---|
| Ubuntu Server | 22.04 LTS | Auch 24.04 funktioniert |
| Docker Engine | 24.x oder neuer | Inkl. Compose v2 (`docker compose`) |
| Git | 2.x | |
| Python 3 | 3.11+ | Einmalig zum Generieren der Secrets |
| OpenSSL | 3.x | Für das Self-signed-Zertifikat |
| GNU Make | optional | Alle Schritte sind als `make`-Targets verfügbar; ohne Make einfach die nackten `docker compose`-Aufrufe im Makefile abschreiben. |
| Freie Ports | 80, 443 | Müssen von außen erreichbar sein |
| VM-IP | z. B. `203.0.113.42` | Die öffentliche IP, unter der die VM erreichbar ist |

RAM/CPU: mindestens 8 GB, 4 vCPU, 50 GB Disk. Der Stack reserviert in Summe ca. 4 GB RAM und 8 CPU-Kerne als Limits.

Die GHCR-Images (`ghcr.io/six7-click-n-deploy/{backend,worker,frontend}`)
sind **öffentlich**. Kein `docker login` nötig.

## Schritt 1: Docker installieren

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

Erwartete Ausgabe: `Docker Compose version v2.x.x`.

## Schritt 2: Repository auf die VM klonen

```bash
sudo mkdir -p /opt/app-store
sudo chown $USER:$USER /opt/app-store
cd /opt/app-store
git clone https://github.com/six7-click-n-deploy/deployment
cd deployment
```

Alle weiteren Befehle aus `/opt/app-store/deployment` ausführen — dort
liegen `docker-compose.prod.yml`, das `Makefile`, das `nginx/`-Verzeichnis
und der Keycloak-Realm-Export.

## Schritt 3: `.env` anlegen

`docker-compose.prod.yml` markiert sämtliche kritischen Werte als
`${VAR:?... is required}` — der Stack startet erst, wenn jeder Pflicht-Wert
gesetzt ist.

```bash
touch .env
chmod 600 .env
```

Die folgenden Felder in `.env` eintragen. Reihenfolge ist egal, Kommentare
mit `#` sind erlaubt.

### 3a. VM-IP als Variable (zur einfacheren Wiederverwendung unten)

Im Folgenden verwende ich `<VM-IP>` als Platzhalter — ersetze ihn überall
durch deine tatsächliche IP-Adresse, z. B. `203.0.113.42`. Wenn du auf
derselben Maschine testest, kann auch `localhost` stehen.

### 3b. Datenbank-Credentials (Pflicht)

Drei voneinander isolierte Postgres-Instanzen — Anwendung, Terraform-State
(Worker), Keycloak. Jede bekommt eigene Credentials. Passwörter generieren
mit `openssl rand -base64 24`.

```
DB_USER=appstore
DB_PASSWORD=<random>
DB_NAME=appstore

TFSTATE_DB_USER=tfstate
TFSTATE_DB_PASSWORD=<random>
TFSTATE_DB_NAME=tfstate

KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=<random>
KEYCLOAK_DB_NAME=keycloak
```

### 3c. RabbitMQ-Credentials (Pflicht)

```
RABBITMQ_USER=appstore
RABBITMQ_PASSWORD=<random>
RABBITMQ_VHOST=/
```

### 3d. Keycloak-Admin (Pflicht)

```
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=<random>
```

Der Admin-User wird beim ersten Keycloak-Boot im `master`-Realm angelegt
— danach lässt sich das Passwort ohne DB-Reset nicht mehr ändern. Den
Wert gut sichern.

### 3e. `SECRET_KEY` (Pflicht)

Symmetrischer Schlüssel für die Backend-JWTs.

```bash
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

```
SECRET_KEY=<output>
```

### 3f. `CREDENTIAL_ENCRYPTION_KEY` (Pflicht)

Symmetrischer Fernet-Key, mit dem Backend und Worker OpenStack-Credentials
ver- und entschlüsseln. Beide Services müssen **denselben** Wert haben
(passiert automatisch, weil das Compose-File den Wert in beide Container
durchreicht).

```bash
python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

```
CREDENTIAL_ENCRYPTION_KEY=<output>
```

Falls `cryptography` lokal nicht installiert ist: `pip install cryptography`
oder `apt install python3-cryptography`.

### 3g. `KEYCLOAK_CLIENT_SECRET` (Platzhalter)

Der echte Wert kann erst nach dem ersten Keycloak-Start aus dem Admin-UI
geholt werden. Für den Erst-Start einen Platzhalter eintragen:

```
KEYCLOAK_CLIENT_SECRET=changeme
```

In Schritt 7 wird der echte Wert nachgetragen.

### 3h. `GIT_ACCESS_TOKEN` (Pflicht)

GitHub Personal Access Token mit `repo`-Scope. Wird vom Worker beim
Klonen privater App-Repos und vom Backend für Hook-Verifikation
verwendet. Anlegen unter: GitHub → Settings → Developer settings →
Personal access tokens (classic) → Generate new token.

```
GIT_ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 3i. URLs (Pflicht)

Alle URLs zeigen auf deine VM. Bei IP-VM ohne DNS sieht das so aus:

```
APP_BASE_URL=https://<VM-IP>
CORS_ORIGINS=https://<VM-IP>

VITE_APP_URL=https://<VM-IP>
VITE_API_URL=https://<VM-IP>/api
VITE_KEYCLOAK_URL=https://<VM-IP>
```

### 3j. `SMTP_*` (optional)

E-Mail-Benachrichtigungen (Approval-Workflow). Wenn du sie nicht
brauchst, einfach `SMTP_ENABLED=false` lassen — der Stack startet
trotzdem und die Mail-Funktionen werden zu No-Ops.

```
SMTP_ENABLED=false
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=
SMTP_FROM_NAME=Click-n-Deploy
```

## Schritt 4: Self-signed-Zertifikat erzeugen

`nginx-prod` terminiert HTTPS auf Port 443 und erwartet zwei Dateien
unter `nginx/certs/`. Generiere beides mit einem Make-Target:

```bash
make prod-cert-self-signed PROD_HOST=<VM-IP>
```

Das Target legt das Verzeichnis an, erzeugt ein 10 Jahre gültiges
Zertifikat mit `CN=<VM-IP>` und `subjectAltName=IP:<VM-IP>,DNS:<VM-IP>`,
setzt die richtigen Permissions und gibt das Ablaufdatum aus. Resultat:

```
nginx/certs/cert.pem      # Public cert
nginx/certs/key.pem       # Private key, 600
```

Browser zeigen beim ersten Aufruf eine Sicherheitswarnung („Verbindung
nicht sicher") — Ausnahme einmal bestätigen und gut.

## Schritt 5: Stack starten

```bash
make prod-up
```

Das lädt zunächst alle `:latest`-Images aus GHCR (`pull_policy: always`)
und startet danach die zehn Container. Erstdurchlauf dauert je nach
Bandbreite 2–5 Minuten.

Status prüfen:

```bash
make prod-ps
```

Alle zehn Container sollten `running (healthy)` melden, sobald die
Healthchecks durchlaufen sind. Falls ein Container im Crash-Loop steckt,
gezielt die Logs anschauen:

```bash
make prod-logs SVC=backend
make prod-logs SVC=keycloak
```

Bevor Schritt 6 läuft, sicherstellen dass Keycloak fertig hochgefahren
ist:

```bash
make prod-logs SVC=keycloak | grep -i "listening on\|started in"
```

Erwartete Zeilen:

```
Listening on: http://0.0.0.0:8080
... started in XX.XXXs
```

`Ctrl-C` beendet das Tail.

## Schritt 6: Datenbank-Migrationen anwenden

Migrationen sind bewusst NICHT Teil der Compose-Datei (eine
Migrate-Init-Container-Variante würde Fehler in der Compose-Output
verstecken). Einmalig per Make-Target anstoßen:

```bash
make prod-migrate
```

Die Ausgabe endet mit `Running upgrade <rev> -> <rev>, …` für jede
Migration. Bei einem leeren Schema werden alle Migrationen
nacheinander ausgeführt; bei aktuellem Schema gibt es keine Ausgabe.

> [!NOTE]
> Die Realm-Daten (Clients, Rollen, Realm-Settings) werden beim ersten
> Start aus `keycloak/realm-export.json` importiert. Test-User wie in
> Dev werden in Prod NICHT geseedet — User müssen manuell im
> Keycloak-Admin-UI angelegt werden.

## Schritt 7: Echtes `KEYCLOAK_CLIENT_SECRET` eintragen

Der importierte Realm bringt den `appstore-backend`-Client mit einem
maskierten Secret-Wert (`**********`) aus dem Realm-Export mit — kein
gültiger Wert. Das echte Secret muss einmalig in Keycloak neu erzeugt
und in die `.env` übernommen werden.

1. `https://<VM-IP>/admin` im Browser öffnen (Cert-Warnung akzeptieren).
2. Mit `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD` aus Schritt 3d
   einloggen.
3. Realm-Switcher oben links: von `master` auf `dhbw` umstellen.
4. Links auf **Clients** → `appstore-backend` öffnen.
5. Reiter **Credentials** → Button **„Regenerate"** klicken.
6. Den Wert kopieren und in `.env` eintragen:

   ```
   KEYCLOAK_CLIENT_SECRET=<kopierter-wert>
   ```

7. Backend neu starten:

   ```bash
   make prod-restart SVC=backend
   ```

Ab jetzt kann das Backend Tokens validieren.

## Schritt 8: Seed-Daten anlegen

Initiale Test-User (Profs, Studenten, ein Admin), die sechs offiziellen
DHBW-Apps und ihre Approval-Datensätze einspielen:

```bash
make prod-seed
```

Was passiert:

1. `seed/seed_data.py`, `seed/app_descriptions/` und der Realm-Export
   werden in den `backend-prod`-Container kopiert.
2. Das Make-Target lädt `.env` im Recipe-Shell und reicht
   `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD` als `-e`-Flags
   an den `docker compose exec`-Aufruf weiter.
3. Das Skript meldet sich damit am Realm `master` an und legt im
   `dhbw`-Realm alle Seed-User an (Standardpasswort: `1234`,
   Login-Format `<vorname>.<nachname>@dhbw.de`).
4. Anschließend werden die User in die Backend-DB gespiegelt, vier
   Kurse erzeugt, Profs als Teacher verlinkt und die sechs Apps
   (Online-IDE, Ubuntu-App, Web-LaTeX, Jupyter-Notebook, pgAdmin,
   GitLab-CE) mit ihren `APPROVED`-Versionen geseedet.

Das Skript ist idempotent — ein zweiter Aufruf aktualisiert nur, was
sich verändert hat, und produziert keine Duplikate.
