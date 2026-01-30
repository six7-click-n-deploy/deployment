# Deployment Repository

Zentrale Orchestrierung für die Entwicklungs- und Produktionsumgebung von Click'n'Deploy.

## Struktur

```
deployment/
├── LICENSE                   # Lizenzdatei
├── Makefile                  # Orchestrierung Befehle
├── README.md                 # Diese Datei
├── docker-compose.dev.yml    # Entwicklungsumgebung
├── docker-compose.prod.yml   # Produktivumgebung
├── .env.example              # Environment Vorlage
├── .env                      # Deine Umgebung (nicht in git)
└── keycloak                  # Keycloak Konfiguration
    └── keycloak-export.json  # Keycloak Realm Export
```

## Installation

### Entwicklungsumgebung einrichten

1) Repositories klonen — lege alle drei Projekte und das `deployment`-Verzeichnis an.

```bash
git clone https://github.com/six7-click-n-deploy/frontend.git
git clone https://github.com/six7-click-n-deploy/backend.git
git clone https://github.com/six7-click-n-deploy/worker.git
git clone https://github.com/six7-click-n-deploy/deployment.git
```

2) In das `deployment`-Verzeichnis wechseln — dort befinden sich `Makefile`, `docker-compose` und `.env`.

```bash
cd deployment
```

3) `.env` erzeugen und bearbeiten — erzeugt eine `deployment/.env` aus der Vorlage und öffne sie anschließend zum Anpassen.

```bash
make env
```

4) (Optional) Dev‑Images lokal bauen — nötig, wenn Dockerfiles oder Abhängigkeiten geändert wurden.

```bash
make dev-build
```

5) Entwicklungsumgebung starten — startet alle Services (Hot‑Reload aktiv).

```bash
make dev-up
```

6) Initiale Datenbankmigrationen ausführen — einmalig nach dem ersten Start oder nach Model‑Änderungen.

```bash
make migrate-dev
```

7) Realm in Keycloak importieren — nur beim ersten Start nötig.

Hierfür muss auf `http://localhost:8080` der Admin‑Account (`admin` / `admin`) genutzt werden. Klicke oben links im Dropdown, wo standardmäßig "master" steht, auf "Create realm" und wähle die Datei `keycloak/keycloak-export.json` als Resource file aus und klicke anschließend auf "Create".

### Zugriff auf Services

```
Frontend:  http://localhost:5173
Backend:   http://localhost:8000
API Docs:  http://localhost:8000/docs
Keycloak:  http://localhost:8080 (admin / admin)
pgAdmin:   http://localhost:5050 (admin@admin.com / admin)
```

## Verfügbare Make‑Commands

Rufe `make help` auf, um die aktuelle, automatisch generierte Liste aller Targets zu sehen:

```bash
make help
```

Kurzübersicht (häufig genutzte Targets)

- `make dev-up` : Startet die komplette Entwicklungsumgebung (Container, Hot‑Reload).
- `make dev-down` : Stoppt die Entwicklungsumgebung.
- `make dev-logs` : Zeigt Logs aller Dev‑Services in Echtzeit.
- `make dev-logs-backend` / `make dev-logs-frontend` / `make dev-logs-worker` : Logs einzelner Services.
- `make dev-build` : Baut alle Development‑Images lokal.
- `make dev-build-backend` / `make dev-build-frontend` / `make dev-build-worker` : Einzelne Images bauen.
- `make dev-rebuild` : Rebuild (no-cache) und neu starten der Dev‑Umgebung.
- `make dev-ps` : Liste der Dev‑Container.

- `make prod-up` / `make prod-down` : Start/Stop der Produktions‑Compose.
- `make prod-pull` : Pull aller Production‑Images.
- `make prod-update` : Pull + Restart der Production‑Services.
- `make prod-logs` / `make prod-logs-backend` / `make prod-logs-frontend` / `make prod-logs-worker` : Produktions‑Logs.

- `make shell-backend` / `make shell-worker` / `make shell-frontend` : Öffnet eine Shell im jeweiligen Dev‑Container.
- `make shell-db` : Öffnet eine `psql`‑Shell gegen die Dev‑Postgres.
- `make shell-keycloak` / `make shell-keycloak-db` : Keycloak Shell bzw. Keycloak‑DB Shell.

- `make migrate-dev` / `make migrate-prod` : Führe Alembic‑Migrations aus (Dev / Prod).
- `make migration-create MSG="..."` : Erzeuge neue Migration mit Message.
- `make migration-history` / `make migration-current` / `make migration-downgrade` : Migrationstools.

- `make db-backup` / `make db-restore FILE=...` : Backup/Restore für Prod‑DB.
- `make db-reset-dev` : Setzt die Dev‑DB zurück (WARNUNG: löscht Daten).

- `make keycloak-up` / `make keycloak-down` / `make keycloak-restart` : Keycloak im Dev starten/stoppen.
- `make keycloak-export` : Exportiert den Realm (z.B. `dhbw`) nach `keycloak/keycloak-export.json`.
- `make keycloak-token USER=... PASS=...` / `make keycloak-userinfo TOKEN=...` : Token und Userinfo Commands.

- `make health` / `make health-prod` : Einfache Health‑Checks (Dev / Prod).
- `make status` / `make status-prod` : Zeigt Container‑Status (Dev / Prod).

- `make stats` : `docker stats` für laufende Container.
- `make watch-dev` / `make watch-prod` : Beobachtet Container‑Status in Intervallen.

- `make test-backend` / `make test-backend-cov` : Backend‑Tests (mit Coverage).
- `make lint-backend` / `make lint-backend-fix` / `make format-backend` : Linting / Formatierung.

- `make clean-dev` / `make clean-prod` / `make clean-all` : Aufräum‑Targets (löschen Container/Volumes).
- `make prune` : Docker System Cleanup (entfernt ungenutzte Ressourcen).

- `make restart-backend` / `make restart-frontend` / `make restart-worker` : Neustart einzelner Dev‑Services.

- Alias‑Targets:
    - `make up` → `make dev-up`
    - `make down` → `make dev-down`
    - `make logs` → `make dev-logs`
    - `make build` → `make dev-build`

Wenn du ein spezifisches Target suchst, nutze `make help` — die Ausgabe listet alle Targets mit ihren Beschreibungen.