# Produktives Setup

Der App Store läuft im Produktivbetrieb auf einer einzelnen Docker-Host-VM (OpenStack, Ubuntu 22.04). Die zehn Container des Produktiv-Stacks — `nginx` (TLS-Terminierung), `frontend`, `backend`, `worker`, `keycloak` (+ Postgres), `postgres` (App-DB), `postgres-tfstate` (Terraform-State des Workers), `rabbitmq`, `redis` — werden über `docker-compose.prod.yml` orchestriert und ausschließlich aus dem GHCR-Image-Registry gezogen (`pull_policy: always`, Tags fest auf `:latest`). Diese Anleitung führt von einer leeren Ubuntu-VM bis zum produktiv erreichbaren Frontend hinter HTTPS.

> [!TIP]
> Der gesamte Ablauf ist in `infrastructure/ansible/` als Playbook automatisiert (analog zur Staging-Pipeline) und wird im Regelbetrieb von CI ausgerollt. Diese Anleitung beschreibt den manuellen Weg — z. B. für die Erst-Provisionierung, eine isolierte Prod-Instanz, oder zum Nachvollziehen, was die Pipeline tut.

## Voraussetzungen

| Werkzeug | Version | Anmerkung |
|---|---|---|
| Ubuntu Server | 22.04 LTS | Auch 24.04 funktioniert |
| Docker Engine | 24.x oder neuer | Inkl. Compose v2 (`docker compose`) |
| Git | 2.x | |
| Python 3 | 3.11+ | Einmalig zum Generieren der Secrets |
| OpenSSL | 3.x | Für die Zertifikatserstellung |
| Freie Ports | 80, 443 | Müssen von außen erreichbar sein |
| Öffentlicher DNS-Name | z. B. `appstore.dhbw.de` | Zeigt auf die VM, wird im Zertifikat verwendet |

Die Prod-Images liegen als **öffentliche** Pakete in GHCR (`ghcr.io/six7-click-n-deploy/{backend,worker,frontend}:latest`), ein Login ist für reine Pulls daher nicht nötig.

RAM: mindestens 8 GB, 4 vCPU, 50 GB Disk empfohlen. Der Stack reserviert in Summe ca. 4 GB RAM und 8 CPU-Kerne als Limits.

Vor dem Start sollte die VM aktualisiert sein:

```bash
sudo apt update && sudo apt upgrade -y
```

## Schritt 1: Docker installieren

Docker Engine inklusive Compose Plugin nach Anleitung von docker.com einrichten und den eigenen User in die `docker`-Gruppe aufnehmen:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

Erwartete Ausgabe: `Docker Compose version v2.x.x`.

## Schritt 2: Repository auf den Server bringen

Auf der Prod-VM wird nur das `deployment/`-Repo benötigt — die Images für `frontend`, `backend` und `worker` werden zur Laufzeit aus GHCR gezogen und nicht lokal gebaut.

```bash
sudo mkdir -p /opt/app-store
sudo chown $USER:$USER /opt/app-store
cd /opt/app-store
git clone https://github.com/six7-click-n-deploy/deployment
cd deployment
```

Alle weiteren Befehle werden aus `/opt/app-store/deployment` ausgeführt — dort liegen `docker-compose.prod.yml`, das `nginx/`-Verzeichnis und die `keycloak/`-Realm-Exportdatei.

## Schritt 3: `.env` anlegen

> [!TIP]
> Auf Anfrage stellen wir eine fertig befüllte `.env`-Vorlage für Prod bereit. In dem Fall genügt es, die Datei nach `deployment/.env` zu legen und mit Schritt 4 weiterzumachen — die folgenden Unterpunkte 3a–3i sind dann nicht nötig.

Im Gegensatz zu Dev gibt es für Prod keine `.env.example` mit Defaults. `docker-compose.prod.yml` markiert sämtliche kritischen Werte mit `${VAR:?... is required}`, d. h. der Stack startet nicht, solange auch nur eine Variable fehlt. Datei anlegen:

```bash
touch .env
chmod 600 .env
```

Die folgenden Felder sind Pflicht. Reihenfolge in der Datei ist egal, Kommentare mit `#` sind erlaubt.

### 3a. Datenbank-Credentials (Pflicht)

Drei voneinander isolierte Postgres-Instanzen — Anwendung, Terraform-State (Worker), Keycloak. Jede bekommt eigene Credentials. Passwörter mit `openssl rand -base64 24` erzeugen.

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

### 3b. RabbitMQ-Credentials (Pflicht)

```
RABBITMQ_USER=appstore
RABBITMQ_PASSWORD=<random>
RABBITMQ_VHOST=/
```

### 3c. Keycloak-Admin (Pflicht)

```
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=<random>
```

Der Admin-User wird beim ersten Keycloak-Boot im `master`-Realm angelegt — danach lässt sich das Passwort ohne DB-Reset nicht mehr ändern. Den Wert gut sichern.

### 3d. `SECRET_KEY` (Pflicht)

Symmetrischer Schlüssel für die Backend-JWTs. Generieren:

```bash
python3 -c 'import secrets; print(secrets.token_hex(32))'
```

```
SECRET_KEY=<output>
```

### 3e. `CREDENTIAL_ENCRYPTION_KEY` (Pflicht)

Symmetrischer Fernet-Key, mit dem Backend und Worker OpenStack-Credentials ver- und entschlüsseln. Beide Services müssen denselben Wert haben.

```bash
python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

```
CREDENTIAL_ENCRYPTION_KEY=<output>
```

Falls `cryptography` lokal nicht installiert ist: `pip install cryptography` (oder `apt install python3-cryptography`).

### 3f. `KEYCLOAK_CLIENT_SECRET` (Platzhalter)

Der echte Wert kann erst nach dem ersten Keycloak-Start aus dem Admin-UI geholt werden. Für den Erst-Start einen Platzhalter eintragen:

```
KEYCLOAK_CLIENT_SECRET=changeme
```

In Schritt 7 wird der echte Wert nachgetragen.

### 3g. `GIT_ACCESS_TOKEN` (Pflicht)

GitHub Personal Access Token mit `repo`-Scope. Wird gebraucht, damit der Worker beim Deployment private App-Repos klonen und das Backend Hooks verifizieren kann. Anlegen unter: GitHub → Settings → Developer settings → Personal access tokens (classic) → Generate new token.

```
GIT_ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GIT_USER=<github-user>
```

### 3h. Öffentliche URLs (Pflicht)

Müssen mit dem Zertifikat aus Schritt 4 und dem DNS-Eintrag der VM übereinstimmen. Beispiel für `appstore.dhbw.de`:

```
APP_BASE_URL=https://appstore.dhbw.de
CORS_ORIGINS=https://appstore.dhbw.de

VITE_APP_URL=https://appstore.dhbw.de
VITE_API_URL=https://appstore.dhbw.de/api
VITE_KEYCLOAK_URL=https://appstore.dhbw.de
```

Alle drei `VITE_*`-Variablen werden beim Frontend-Build in das SPA gebaked — eine Änderung erfordert anschließend `docker compose -f docker-compose.prod.yml up -d --force-recreate frontend`.

### 3i. `SMTP_*` (optional)

E-Mail-Benachrichtigungen (Approval-Workflow). Wenn nicht gebraucht, einfach `SMTP_ENABLED=false` lassen und die anderen Felder leer. Für Gmail ein App-Password verwenden, nicht das Account-Passwort.

```
SMTP_ENABLED=false
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=
SMTP_FROM_NAME=Click-n-Deploy
```

## Schritt 4: TLS-Zertifikat einrichten

`nginx-prod` terminiert HTTPS auf Port 443 und erwartet zwei bind-gemountete Dateien:

```
nginx/certs/cert.pem      # Zertifikat (PEM, ggf. inkl. Zwischenzertifikate)
nginx/certs/key.pem       # Privater Schlüssel (PEM, ohne Passphrase)
```

Verzeichnis anlegen:

```bash
mkdir -p nginx/certs
chmod 700 nginx/certs
```

Eine der drei folgenden Optionen wählen:

### 4a. Variante A: Self-signed (intern, schnellster Weg)

Für interne Deployments oder reine Testumgebungen, bei denen Browser-Warnungen akzeptabel sind. Gültigkeit 10 Jahre, Common Name + SAN auf den DNS-Namen bzw. die IP:

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout nginx/certs/key.pem \
  -out    nginx/certs/cert.pem \
  -subj   "/CN=appstore.dhbw.de" \
  -addext "subjectAltName=DNS:appstore.dhbw.de,IP:<vm-ip>"
chmod 600 nginx/certs/key.pem
chmod 644 nginx/certs/cert.pem
```

Beim ersten Browserzugriff erscheint eine Warnung ("Verbindung nicht sicher") — Ausnahme einmal bestätigen.

### 4b. Variante B: Let's Encrypt (öffentlich erreichbar, kostenlos)

Wenn die VM aus dem Internet auf Port 80 erreichbar ist und ein gültiger DNS-A-Record existiert. Certbot direkt auf der Host-Maschine, im Standalone-Modus (nginx ist beim Erst-Erzeugen noch nicht gestartet):

```bash
sudo apt install -y certbot
sudo certbot certonly --standalone \
  -d appstore.dhbw.de \
  --agree-tos -m admin@dhbw.de --non-interactive
```

Anschließend die ausgegebenen Dateien an die von nginx erwartete Stelle kopieren:

```bash
sudo cp /etc/letsencrypt/live/appstore.dhbw.de/fullchain.pem nginx/certs/cert.pem
sudo cp /etc/letsencrypt/live/appstore.dhbw.de/privkey.pem   nginx/certs/key.pem
sudo chown $USER:$USER nginx/certs/*.pem
chmod 600 nginx/certs/key.pem
```

Verlängerung: Certbot installiert automatisch einen systemd-Timer (`certbot.timer`). Damit die erneuerten Dateien auch nach `nginx/certs/` kopiert und in nginx neu geladen werden, einen Deploy-Hook hinterlegen:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/appstore-reload.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -e
APP=/opt/app-store/deployment
cp /etc/letsencrypt/live/appstore.dhbw.de/fullchain.pem $APP/nginx/certs/cert.pem
cp /etc/letsencrypt/live/appstore.dhbw.de/privkey.pem   $APP/nginx/certs/key.pem
docker exec nginx-prod sh -c 'nginx -t && nginx -s reload'
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/appstore-reload.sh
```

Renewal testen:

```bash
sudo certbot renew --dry-run
```

### 4c. Variante C: Bereits vorhandenes Zertifikat einer CA (DHBW PKI o. ä.)

Wenn ein offizielles Zertifikat von der Hochschul-/Firmen-CA vorliegt, die beiden Dateien direkt einspielen:

```bash
cp /pfad/zur/fullchain.pem nginx/certs/cert.pem
cp /pfad/zum/privatekey.pem nginx/certs/key.pem
chmod 600 nginx/certs/key.pem
chmod 644 nginx/certs/cert.pem
```

`cert.pem` sollte die vollständige Kette enthalten (Server-Zertifikat + alle Zwischen-Zertifikate, in dieser Reihenfolge). Reine Server-Zertifikate ohne Chain führen bei strengen Clients zu Verbindungsfehlern.

### Verifikation des Zertifikats

Vor dem Start prüfen, dass beide Dateien lesbar sind und der Schlüssel zum Zertifikat passt:

```bash
openssl x509 -in nginx/certs/cert.pem -noout -subject -dates -issuer
diff <(openssl x509 -in nginx/certs/cert.pem -noout -pubkey) \
     <(openssl pkey  -in nginx/certs/key.pem  -pubout)
```

Der `diff` darf nichts ausgeben — sobald Unterschiede erscheinen, gehören Cert und Key nicht zusammen.

## Schritt 5: Stack starten

```bash
docker compose -f docker-compose.prod.yml up -d --pull always
```

`--pull always` pullt vor dem Start die aktuellen `:latest`-Images aus GHCR. Beim ersten Start dauert das 2–5 Minuten (Image-Pull + Keycloak-Init). Status prüfen:

```bash
docker compose -f docker-compose.prod.yml ps
```

Alle zehn Container sollten `running (healthy)` melden, sobald die Healthchecks durchlaufen sind. Wenn ein Container im Loop crasht, gezielt die Logs anschauen:

```bash
docker compose -f docker-compose.prod.yml logs -f backend
docker compose -f docker-compose.prod.yml logs -f keycloak
```

Bevor Schritt 6 läuft, sicherstellen dass Keycloak fertig ist:

```bash
docker compose -f docker-compose.prod.yml logs keycloak | grep -i "listening on\|started in"
```

Erwartete Zeilen:

```
Listening on: http://0.0.0.0:8080
... started in XX.XXXs
```

## Schritt 6: Datenbank-Migrationen anwenden

Migrationen sind bewusst NICHT Teil der Compose-Datei (eine eigene Migrate-Init-Container-Variante würde Fehler im Compose-Output verstecken). Stattdessen einmalig per `docker exec` anstoßen:

```bash
docker exec backend-prod python -m alembic upgrade head
```

Die Ausgabe endet mit `Running upgrade <revision> -> <revision>, …` für jede angewendete Migration. Bei einem leeren Schema werden alle Migrationen nacheinander ausgeführt; bei einem bereits aktuellen Schema gibt es keine Ausgabe.

> [!NOTE]
> Die Realm-Daten (Clients, Rollen, Realm-Settings) werden beim ersten Start aus `keycloak/realm-export.json` importiert. Test-User wie in Dev (`tobias.admin@dhbw.de`, …) werden in Prod NICHT geseedet — User müssen manuell im Keycloak-Admin angelegt oder über einen Identity Provider föderiert werden.

## Schritt 7: Echtes `KEYCLOAK_CLIENT_SECRET` eintragen

Der importierte Realm bringt den `appstore-backend`-Client mit dem maskierten Secret `**********` aus dem Realm-Export mit — kein gültiger Wert. Das echte Secret muss einmalig in Keycloak neu erzeugt und in die `.env` übernommen werden.

1. `https://appstore.dhbw.de/admin` im Browser öffnen (das Self-signed-Zertifikat ggf. einmal akzeptieren).
2. Mit `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD` aus Schritt 3c einloggen.
3. Oben links im Realm-Switcher von `master` auf `dhbw` umstellen.
4. Links auf "Clients" → `appstore-backend` öffnen.
5. Reiter "Credentials" → Button **"Regenerate"** klicken.
6. Den neu generierten Wert kopieren und in `.env` eintragen:

   ```
   KEYCLOAK_CLIENT_SECRET=<kopierter-wert>
   ```

7. Backend neu starten:

   ```bash
   docker compose -f docker-compose.prod.yml up -d --force-recreate backend
   ```

Ab jetzt kann das Backend Tokens validieren.

## Verifikation

Smoke-Test gegen die wichtigsten Endpoints (URLs an euren DNS-Namen anpassen):

```bash
curl -fsS https://appstore.dhbw.de/api/health
curl -fsS https://appstore.dhbw.de/realms/dhbw/.well-known/openid-configuration | head
```

Oder im Browser einzeln öffnen:

| Dienst | URL | Erwartet |
|---|---|---|
| Frontend | https://appstore.dhbw.de | Click-n-Deploy Login-Seite |
| Backend Health | https://appstore.dhbw.de/api/health | `{"status":"ok"}` |
| Keycloak Admin | https://appstore.dhbw.de/admin | Keycloak Welcome, Login mit Admin-Credentials |
| Keycloak OIDC Discovery | https://appstore.dhbw.de/realms/dhbw/.well-known/openid-configuration | JSON mit `issuer: https://appstore.dhbw.de/realms/dhbw` |

Token-Check auf der Kommandozeile (User vorher in Keycloak anlegen):

```bash
curl -s -X POST https://appstore.dhbw.de/realms/dhbw/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=appstore-frontend" \
  -d "username=<email>" -d "password=<password>" \
  -d "grant_type=password" | jq -r '.access_token' | head -c 50; echo "..."
```

Liefert die ersten 50 Zeichen eines JWT. `invalid_grant` deutet auf falsche User-Credentials oder einen nicht-aktivierten User hin.

## Login

Im Browser `https://appstore.dhbw.de` öffnen, "Login" klicken. Da in Prod keine Seed-User existieren, müssen User vorab im Keycloak-Admin-UI (Realm `dhbw` → Users → Add user) oder über die User-API angelegt werden. E-Mail-Konvention wie in Dev: `<vorname>.<nachname>@dhbw.de`, alles klein, Umlaute ersetzt (`ä → ae`, `ö → oe`, `ü → ue`, `ß → ss`). Der Keycloak-Admin ist NICHT identisch mit Realm-Usern — er funktioniert nur unter `/admin`, nicht im Frontend.

## Stoppen, Neustarten, Zurücksetzen

### Sauber stoppen (Daten bleiben)

```bash
docker compose -f docker-compose.prod.yml down
```

Container weg, Volumes (DBs, Keycloak-Daten, RabbitMQ-Persistenz) bleiben. Beim nächsten `compose up` startet alles im Zustand vor dem Stopp.

### Nur pausieren (schnellster Re-Start)

```bash
docker compose -f docker-compose.prod.yml stop
docker compose -f docker-compose.prod.yml up -d
```

### Einzelnen Dienst neu starten

```bash
docker compose -f docker-compose.prod.yml restart backend
docker compose -f docker-compose.prod.yml restart frontend
docker compose -f docker-compose.prod.yml restart worker
```

### Update auf neueste Images ziehen

Da alle Service-Images auf `:latest` mit `pull_policy: always` stehen, reicht ein erneutes `up`:

```bash
docker compose -f docker-compose.prod.yml up -d --pull always
docker exec backend-prod python -m alembic upgrade head   # falls neue Migrationen dabei sind
```

Soll explizit ein bestimmter Commit-/Image-Stand laufen statt `:latest`, ist `docker-compose.staging.yml` die richtige Variante (dort sind die Tags über `${BACKEND_VERSION:-latest}` etc. pinnbar).

### Logs verfolgen

```bash
docker compose -f docker-compose.prod.yml logs -f                # alle
docker compose -f docker-compose.prod.yml logs -f backend        # nur Backend
docker compose -f docker-compose.prod.yml logs -f worker         # nur Worker
docker compose -f docker-compose.prod.yml logs -f keycloak       # nur Keycloak
docker compose -f docker-compose.prod.yml logs -f nginx          # nur nginx (TLS-Handshakes etc.)
```

### nginx-Konfiguration neu laden

Nach einer Änderung an `nginx/nginx.conf` (z. B. neue Route, geänderte Header) ohne Container-Neustart neu laden:

```bash
docker exec nginx-prod sh -c 'nginx -t && nginx -s reload'
```

`nginx -t` validiert die Konfiguration vorher — bei einem Syntaxfehler bleibt nginx auf der alten, lauffähigen Version.

### Komplett zurücksetzen (alle Daten weg)

> [!CAUTION]
> Folgender Befehl löscht ALLE Daten — Deployments, User, Keycloak-Realm, Terraform-State. In Prod normalerweise NICHT verwenden.

```bash
docker compose -f docker-compose.prod.yml down -v
```

Nach `down -v` startet der nächste `compose up` mit leeren Volumes — Migrationen und Keycloak-Realm-Import laufen erneut, der `KEYCLOAK_CLIENT_SECRET`-Workflow aus Schritt 7 muss wiederholt werden.
