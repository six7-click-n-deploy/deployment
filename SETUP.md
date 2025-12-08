# 🎯 Deployment Template Files - Übersicht

Dieses Verzeichnis enthält **Template-Dateien** für das `deployment` Repository.

## 📋 Dateien zum Kopieren

Kopiere folgende Dateien in das `deployment` Repository:

```bash
deployment/
├── docker-compose.dev.yml      # ← Aus diesem Ordner kopieren
├── docker-compose.prod.yml     # ← Aus diesem Ordner kopieren
├── Makefile                    # ← Aus diesem Ordner kopieren
├── .env.example               # ← Aus diesem Ordner kopieren
└── README.md                  # ← Aus diesem Ordner kopieren
```

## 🚀 Anleitung

### 1. Dateien ins deployment Repo kopieren

```bash
# Gehe zum deployment Repo
cd /path/to/deployment

# Kopiere alle Template-Dateien
cp /path/to/backend/deployment-templates/* .

# Erstelle .env aus Template
cp .env.example .env

# Generiere SECRET_KEY
python3 -c "import secrets; print(secrets.token_hex(32))"
# → Kopiere Output in .env

# Editiere .env mit deinen Werten
nano .env
```

### 2. Verzeichnisstruktur prüfen

Stelle sicher, dass alle Repos auf gleicher Ebene liegen:

```
project/
├── backend/           # Backend API code
├── frontend/          # Frontend code
├── worker/            # Worker code
└── deployment/        # Docker Compose & Makefile ← Start hier!
```

### 3. Development starten

```bash
cd deployment

# Services starten
make dev-up

# Migrations ausführen
make migrate-dev

# Logs anschauen
make dev-logs
```

### 4. Production vorbereiten

```bash
cd deployment

# .env für Production anpassen
nano .env

# Setze:
# - BACKEND_VERSION=latest (oder specific tag)
# - FRONTEND_VERSION=latest
# - WORKER_VERSION=latest
# - Sichere Passwörter
# - Production CORS_ORIGINS
# - Starken SECRET_KEY

# Images pullen
make prod-pull

# Services starten
make prod-up

# Status prüfen
make status-prod
```

## 📝 Was wurde angepasst?

### docker-compose.dev.yml
- ✅ Build Context zeigt auf `../backend`, `../frontend`, `../worker`
- ✅ Verwendet `Dockerfile.dev` für Hot Reload
- ✅ Source Code wird gemountet
- ✅ Separate Networks (frontend, backend, worker)
- ✅ pgAdmin für DB-Management

### docker-compose.prod.yml
- ✅ Pulled Images von `ghcr.io/six7-click-n-deploy/`
- ✅ Separate Migration Init-Container
- ✅ Resource Limits gesetzt
- ✅ Health Checks aktiviert
- ✅ Logging konfiguriert
- ✅ Separate Networks

### Makefile
- ✅ 60+ Commands für beide Environments
- ✅ Dev/Prod Trennung
- ✅ Service-spezifische Commands
- ✅ Migration Management
- ✅ Database Backup/Restore
- ✅ Shell Access Commands
- ✅ Testing & Linting
- ✅ Health Checks

### .env.example
- ✅ Alle nötigen Variablen
- ✅ Image Version Tags
- ✅ Service Ports
- ✅ Security Settings
- ✅ Dokumentation

## 🔄 Workflow nach Setup

### Development
```bash
cd deployment

# Starten
make dev-up

# Code in ../backend, ../frontend, ../worker editieren
# → Hot Reload aktiv, keine Rebuilds nötig!

# Migration erstellen (nach Model-Änderungen)
make migration-create MSG="Add field"
make migrate-dev

# Logs
make dev-logs
make dev-logs-backend

# Shell Access
make shell-backend
make shell-db

# Stoppen
make dev-down
```

### Production
```bash
cd deployment

# Images aktualisieren
make prod-pull

# Starten/Updaten
make prod-up

# Status
make status-prod
make health-prod

# Logs
make prod-logs
make prod-logs-backend

# Backup
make db-backup
```

## 🗂️ Backend Repo Änderungen

Im Backend Repo wurden entfernt:
- ❌ `docker-compose.dev.yml` (jetzt in deployment)
- ❌ `docker-compose.prod.yml` (jetzt in deployment)
- ❌ `Makefile` (jetzt in deployment)

Im Backend Repo bleiben:
- ✅ `Dockerfile` (Production Image)
- ✅ `Dockerfile.dev` (Development Image)
- ✅ `start.sh` (Production Startup)
- ✅ Application Code
- ✅ Alembic Migrations
- ✅ Dokumentation

## 📚 Dokumentation

- **deployment/README.md** - Haupt-Anleitung für Deployment
- **backend/DEVELOPMENT.md** - Backend Development Guide
- **backend/MIGRATIONS.md** - Database Migrations
- **backend/DOCKER.md** - Docker Image Details

## ✨ Features

### Development
- 🔥 Hot Reload für alle Services
- 📊 pgAdmin Database UI
- 🔍 Source Code Mounting
- 🚀 Schnelles Iterieren
- 🛠️ Alle Dev-Tools inkludiert

### Production
- 🐳 Images von GitHub Container Registry
- 🔐 Non-root User
- 🏥 Health Checks
- 📈 Resource Limits
- 📝 Structured Logging
- 🔄 Separate Migration Container
- 🌐 Network Isolation

## 🎯 Nächste Schritte

1. ✅ Kopiere Template-Dateien ins `deployment` Repo
2. ✅ Erstelle `.env` und fülle Werte
3. ✅ Prüfe Verzeichnisstruktur (alle Repos auf gleicher Ebene)
4. ✅ Starte Development: `make dev-up`
5. ✅ Teste Services
6. ✅ Commite deployment Repo
7. ✅ Setup CI/CD für Image Builds
8. ✅ Deploy Production: `make prod-pull && make prod-up`

## 🆘 Support

Bei Fragen oder Problemen:
- Backend Issues: https://github.com/six7-click-n-deploy/backend/issues
- Deployment Issues: https://github.com/six7-click-n-deploy/deployment/issues

---

**Happy Deploying! 🚀**
