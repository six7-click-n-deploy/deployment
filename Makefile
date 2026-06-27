# ================================================================
# Makefile for Multi-Repo Deployment
# Manages frontend, backend, worker, keycloak, postgres, redis,
# rabbitmq + pgAdmin in development; frontend, backend, worker,
# postgres, rabbitmq in production.
# ================================================================
#
# Conventions:
# - All recipes that produce no file are listed in .PHONY below.
# - Compose-file paths live in $(DC_DEV) / $(DC_PROD) so we never
#   re-spell "docker-compose.*.yml" in two recipes.
# - Help is generated from `## comments` on the target line — keep
#   them short, they are shown in the `make help` overview.
#
# Default goal is `help`, so a bare `make` is always safe.

# ----------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------
DC_DEV  := docker compose -f docker-compose.dev.yml
DC_PROD := docker compose -f docker-compose.prod.yml

# Host-Ports (müssen mit den ${...:-default} Werten in den compose-
# Dateien übereinstimmen, sonst zeigt `make urls` falsche Links).
FRONTEND_PORT_DEV  ?= 5173
FRONTEND_PORT_PROD ?= 3000
BACKEND_PORT       ?= 8000
KEYCLOAK_PORT      ?= 8080
RABBITMQ_UI_PORT   ?= 15672
PGADMIN_PORT       ?= 5050

.DEFAULT_GOAL := help

.PHONY: help \
        env secret \
        init quickstart urls \
        dev-up dev-down dev-stop dev-restart dev-restart-backend dev-restart-frontend dev-restart-worker \
        dev-logs dev-logs-backend dev-logs-frontend dev-logs-worker dev-logs-keycloak \
        dev-build dev-build-backend dev-build-frontend dev-build-worker dev-rebuild dev-ps \
        prod-up prod-down prod-restart prod-restart-backend prod-restart-frontend prod-restart-worker \
        prod-logs prod-logs-backend prod-logs-frontend prod-logs-worker \
        prod-build prod-pull prod-ps prod-update \
        shell-backend shell-backend-prod shell-worker shell-worker-prod shell-frontend \
        shell-db shell-db-prod shell-redis shell-redis-prod shell-keycloak shell-keycloak-db \
        keycloak-up keycloak-down keycloak-restart keycloak-logs keycloak-ps keycloak-reset \
        keycloak-export keycloak-token keycloak-userinfo keycloak-url \
        seed-data seed-reset \
        migrate-dev migrate-prod migration-create migration-history migration-current migration-downgrade \
        db-backup db-restore db-reset-dev \
        health health-prod status status-prod \
        stats watch-dev watch-prod top top-prod \
        clean-dev clean-prod clean-all prune \
        test-backend test-backend-cov lint-backend lint-backend-fix format-backend \
        up down logs build

# ----------------------------------------------------------------
# Help
# ----------------------------------------------------------------
help: ## Show this help message
	@echo "🚀 Click-n-Deploy – Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Services (dev): frontend, backend, worker, keycloak, postgres,"
	@echo "                postgres-test, postgres-tfstate, keycloak-postgres,"
	@echo "                redis, rabbitmq, pgadmin"
	@echo "Services (prod): frontend, backend, worker, postgres, postgres-tfstate,"
	@echo "                 rabbitmq"
	@echo ""
	@echo "Bootstrap a fresh checkout:  make init"
	@echo "Show URLs:                   make urls"
	@echo ""

# ----------------------------------------------------------------
# Environment Setup
# ----------------------------------------------------------------
env: ## Create .env from template
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "✓ .env file created from template"; \
		echo "⚠️  Please edit .env with your actual values"; \
	else \
		echo ".env file already exists"; \
	fi

secret: ## Generate a new secret key (prints SECRET_KEY=...)
	@python3 -c "import secrets; print('SECRET_KEY=' + secrets.token_hex(32))"

# ----------------------------------------------------------------
# Bootstrap (Top-Level Helper)
# ----------------------------------------------------------------
# Bringt eine frische Arbeitskopie in einen lauffähigen Zustand.
# Reihenfolge: .env anlegen → Services hochfahren → DB-Schema
# applizieren → Beispiel-Daten einseeden. Wenn das .env-File schon
# existiert, lässt env es in Ruhe, also auch zum "auf den neuesten
# Stand bringen" verwendbar.
init: quickstart ## Alias for `quickstart`
quickstart: ## One-shot: env + dev-up + migrate-dev + seed-data
	@$(MAKE) --no-print-directory env
	@$(MAKE) --no-print-directory dev-up
	@echo "⏳ Warte 10s bis Backend/Postgres bereit sind..."
	@sleep 10
	@$(MAKE) --no-print-directory migrate-dev
	@$(MAKE) --no-print-directory seed-data
	@echo ""
	@echo "✓ Quickstart abgeschlossen."
	@$(MAKE) --no-print-directory urls

urls: ## Show all dev URLs in one place
	@echo "🌐 Dev URLs:"
	@echo ""
	@echo "  Frontend:           http://localhost:$(FRONTEND_PORT_DEV)"
	@echo "  Backend API:        http://localhost:$(BACKEND_PORT)"
	@echo "  Backend API Docs:   http://localhost:$(BACKEND_PORT)/docs"
	@echo "  Keycloak Admin:     http://localhost:$(KEYCLOAK_PORT)/admin   (admin / admin)"
	@echo "  Keycloak Realm:     http://localhost:$(KEYCLOAK_PORT)/realms/dhbw"
	@echo "  RabbitMQ UI:        http://localhost:$(RABBITMQ_UI_PORT)       (admin / admin)"
	@echo "  pgAdmin:            http://localhost:$(PGADMIN_PORT)            (admin@admin.com / admin)"
	@echo ""

# ----------------------------------------------------------------
# Development Environment
# ----------------------------------------------------------------
dev-up: ## Start development environment
	$(DC_DEV) up -d
	@echo ""
	@echo "✓ Development environment started"
	@$(MAKE) --no-print-directory urls

dev-down: ## Stop dev environment (keeps volumes)
	$(DC_DEV) down

dev-stop: ## Stop dev containers without removing them
	$(DC_DEV) stop

dev-restart: ## Restart dev environment
	$(DC_DEV) restart

dev-restart-backend: ## Restart backend only (e.g. after editing celery_app.py)
	$(DC_DEV) restart backend

dev-restart-frontend: ## Restart frontend only
	$(DC_DEV) restart frontend

dev-restart-worker: ## Restart worker only (after editing worker/app/tasks.py)
	$(DC_DEV) restart worker

dev-logs: ## Follow dev logs (all services)
	$(DC_DEV) logs -f

dev-logs-backend: ## Follow backend logs
	$(DC_DEV) logs -f backend

dev-logs-frontend: ## Follow frontend logs
	$(DC_DEV) logs -f frontend

dev-logs-worker: ## Follow worker logs
	$(DC_DEV) logs -f worker

dev-logs-keycloak: ## Follow Keycloak logs
	$(DC_DEV) logs -f keycloak

dev-build: ## Build all dev images
	$(DC_DEV) build

dev-build-backend: ## Build backend dev image only
	$(DC_DEV) build backend

dev-build-frontend: ## Build frontend dev image only
	$(DC_DEV) build frontend

dev-build-worker: ## Build worker dev image only
	$(DC_DEV) build worker

dev-rebuild: ## Rebuild from scratch and restart dev
	$(DC_DEV) down
	$(DC_DEV) build --no-cache
	$(DC_DEV) up -d

dev-ps: ## List dev containers
	$(DC_DEV) ps

# ----------------------------------------------------------------
# Production Environment
# ----------------------------------------------------------------
prod-up: ## Start production environment
	$(DC_PROD) up -d
	@echo "✓ Production environment started"

prod-down: ## Stop production environment
	$(DC_PROD) down

prod-restart: ## Restart production environment
	$(DC_PROD) restart

prod-restart-backend: ## Restart backend (prod) only
	$(DC_PROD) restart backend

prod-restart-frontend: ## Restart frontend (prod) only
	$(DC_PROD) restart frontend

prod-restart-worker: ## Restart worker (prod) only
	$(DC_PROD) restart worker

prod-logs: ## Follow prod logs (all services)
	$(DC_PROD) logs -f

prod-logs-backend: ## Follow backend (prod) logs
	$(DC_PROD) logs -f backend

prod-logs-frontend: ## Follow frontend (prod) logs
	$(DC_PROD) logs -f frontend

prod-logs-worker: ## Follow worker (prod) logs
	$(DC_PROD) logs -f worker

prod-build: ## Build prod images locally (rarely needed — CI usually pushes them)
	$(DC_PROD) build

prod-pull: ## Pull latest production images from registry
	$(DC_PROD) pull

prod-ps: ## List prod containers
	$(DC_PROD) ps

prod-update: ## Update production (pull + up -d)
	$(DC_PROD) pull
	$(DC_PROD) up -d
	@echo "✓ Production environment updated"

# ----------------------------------------------------------------
# Shell Access
# ----------------------------------------------------------------
shell-backend: ## Open bash in backend container (dev)
	$(DC_DEV) exec backend bash

shell-backend-prod: ## Open bash in backend container (prod)
	$(DC_PROD) exec backend bash

shell-worker: ## Open bash in worker container (dev)
	$(DC_DEV) exec worker bash

shell-worker-prod: ## Open bash in worker container (prod)
	$(DC_PROD) exec worker bash

shell-frontend: ## Open sh in frontend container (dev)
	$(DC_DEV) exec frontend sh

shell-db: ## Open psql in dev Postgres (backend_dev)
	$(DC_DEV) exec postgres psql -U postgres -d backend_dev

shell-db-prod: ## Open psql in prod Postgres
	$(DC_PROD) exec postgres psql -U postgres

shell-redis: ## Open redis-cli (dev)
	$(DC_DEV) exec redis redis-cli

shell-redis-prod: ## Open redis-cli (prod)
	$(DC_PROD) exec redis redis-cli

shell-keycloak: ## Open bash in Keycloak container (dev)
	$(DC_DEV) exec keycloak bash

shell-keycloak-db: ## Open psql in Keycloak Postgres (dev)
	$(DC_DEV) exec keycloak-postgres psql -U keycloak -d keycloak

# ----------------------------------------------------------------
# Keycloak Management
# ----------------------------------------------------------------
keycloak-up: ## Start Keycloak + its Postgres only
	$(DC_DEV) up -d keycloak-postgres keycloak
	@echo "✓ Keycloak: http://localhost:$(KEYCLOAK_PORT)/admin   (admin / admin)"

keycloak-down: ## Stop Keycloak only
	$(DC_DEV) stop keycloak keycloak-postgres

keycloak-restart: ## Restart Keycloak only
	$(DC_DEV) restart keycloak

keycloak-logs: ## Follow Keycloak logs
	$(DC_DEV) logs -f keycloak

keycloak-ps: ## Show Keycloak container status
	$(DC_DEV) ps keycloak keycloak-postgres

keycloak-reset: ## ⚠️  Reset Keycloak (DROPS realm + users)
	@echo "⚠️  WARNING: This will delete all Keycloak data (realms, users, clients)!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(DC_DEV) stop keycloak keycloak-postgres; \
		$(DC_DEV) rm -f keycloak keycloak-postgres; \
		docker volume rm deployment_keycloak_postgres_data 2>/dev/null || true; \
		$(DC_DEV) up -d keycloak-postgres; \
		sleep 5; \
		$(DC_DEV) up -d keycloak; \
		echo "✓ Keycloak reset complete"; \
		echo "  Login: admin / admin"; \
	fi

keycloak-export: ## Export the dhbw realm to keycloak/keycloak-export.json
	@echo "Exporting Keycloak realm 'dhbw'..."
	$(DC_DEV) exec keycloak /opt/keycloak/bin/kc.sh export --dir /tmp --realm dhbw
	$(DC_DEV) cp keycloak:/tmp/dhbw-realm.json ./keycloak/keycloak-export.json
	@echo "✓ Realm exported → keycloak/keycloak-export.json"

keycloak-token: ## Get a token (usage: make keycloak-token USER=luca.baeck PASS=1234)
	@curl -s -X POST http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/protocol/openid-connect/token \
		-H "Content-Type: application/x-www-form-urlencoded" \
		-d "client_id=appstore-frontend" \
		-d "username=$(USER)" \
		-d "password=$(PASS)" \
		-d "grant_type=password" | jq -r '.access_token' | head -c 50; echo "..."

keycloak-userinfo: ## Decode userinfo (usage: make keycloak-userinfo TOKEN=xxx)
	@curl -s http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/protocol/openid-connect/userinfo \
		-H "Authorization: Bearer $(TOKEN)" | jq

keycloak-url: ## Print Keycloak URLs
	@echo "🔐 Keycloak URLs:"
	@echo ""
	@echo "  Admin Console:   http://localhost:$(KEYCLOAK_PORT)/admin"
	@echo "  Realm dhbw:      http://localhost:$(KEYCLOAK_PORT)/realms/dhbw"
	@echo "  OIDC Config:     http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/.well-known/openid-configuration"
	@echo "  Token Endpoint:  http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/protocol/openid-connect/token"
	@echo "  User Info:       http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/protocol/openid-connect/userinfo"
	@echo ""

# ----------------------------------------------------------------
# Seed Data
# ----------------------------------------------------------------
# Lädt Profs/Studenten/Admin in Keycloak (Realm ``dhbw``) und Kurse,
# Apps + Approval-Records in die Backend-DB. Idempotent — beliebig oft
# wiederholbar; Passwörter werden bei jedem Lauf auf den Default
# zurückgesetzt. Standardpasswort: 1234. Login: <vorname>.<nachname>@dhbw.de
#
# Voraussetzung: ``make dev-up`` lief (Backend + Keycloak gesund).
seed-data: ## Seed Keycloak users + DB (courses, apps, approvals)
	@echo "📥 Kopiere Seed-Skript in den Backend-Container..."
	$(DC_DEV) cp ./seed/seed_data.py backend:/tmp/seed_data.py
	@echo "🌱 Führe Seed aus..."
	$(DC_DEV) exec -T \
		-e KEYCLOAK_ADMIN_USER=$${KEYCLOAK_ADMIN_USER:-admin} \
		-e KEYCLOAK_ADMIN_PASSWORD=$${KEYCLOAK_ADMIN_PASSWORD:-admin} \
		backend python /tmp/seed_data.py

seed-reset: ## ⚠️  Reset DB + Keycloak realm, then seed
	@echo "⚠️  WARNING: This will reset the dev DB AND the Keycloak realm!"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) --no-print-directory db-reset-dev REPLY=y; \
		$(MAKE) --no-print-directory keycloak-reset REPLY=y; \
		$(MAKE) --no-print-directory seed-data; \
	fi

# ----------------------------------------------------------------
# Database Migrations
# ----------------------------------------------------------------
migrate-dev: ## Run alembic upgrade head (dev)
	$(DC_DEV) exec backend poetry run alembic upgrade head

migrate-prod: ## Run alembic upgrade head (prod)
	$(DC_PROD) exec backend alembic upgrade head

migration-create: ## Autogenerate migration (usage: make migration-create MSG="message")
	@if [ -z "$(MSG)" ]; then \
		echo "Error: Please provide a message. Usage: make migration-create MSG='Your message'"; \
		exit 1; \
	fi
	$(DC_DEV) exec backend poetry run alembic revision --autogenerate -m "$(MSG)"

migration-history: ## Show migration history (dev)
	$(DC_DEV) exec backend poetry run alembic history

migration-current: ## Show current migration (dev)
	$(DC_DEV) exec backend poetry run alembic current

migration-downgrade: ## Downgrade by one revision (dev)
	$(DC_DEV) exec backend poetry run alembic downgrade -1

# ----------------------------------------------------------------
# Database Management
# ----------------------------------------------------------------
db-backup: ## pg_dump production DB into backup_<timestamp>.sql
	$(DC_PROD) exec postgres pg_dump -U postgres > backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "✓ Database backed up"

db-restore: ## Restore prod DB (usage: make db-restore FILE=backup.sql)
	@if [ -z "$(FILE)" ]; then \
		echo "Error: Please provide a backup file. Usage: make db-restore FILE=backup.sql"; \
		exit 1; \
	fi
	$(DC_PROD) exec -T postgres psql -U postgres < $(FILE)

db-reset-dev: ## ⚠️  Wipe + re-create dev DB (DROPS ALL DATA, runs migrations)
	@echo "⚠️  WARNING: This will delete all development database data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(DC_DEV) down -v; \
		$(DC_DEV) up -d; \
		sleep 8; \
		$(MAKE) --no-print-directory migrate-dev; \
		echo "✓ Development database reset complete"; \
	fi

# ----------------------------------------------------------------
# Health & Status
# ----------------------------------------------------------------
health: ## Check service health (dev)
	@echo "🏥 Checking service health..."
	@echo ""
	@printf "  Backend:   "; curl -sf http://localhost:$(BACKEND_PORT)/health > /dev/null && echo "✓ healthy" || echo "❌ not healthy"
	@printf "  Frontend:  "; curl -sf http://localhost:$(FRONTEND_PORT_DEV) > /dev/null && echo "✓ healthy" || echo "❌ not healthy"
	@printf "  Keycloak:  "; curl -sf http://localhost:$(KEYCLOAK_PORT)/realms/dhbw/.well-known/openid-configuration > /dev/null && echo "✓ healthy" || echo "❌ not healthy"
	@echo ""

health-prod: ## Check production container status
	@echo "🏥 Production container status..."
	@$(DC_PROD) ps

status: ## Container status (dev)
	$(DC_DEV) ps

status-prod: ## Container status (prod)
	$(DC_PROD) ps

# ----------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------
stats: ## docker stats (all containers)
	docker stats

watch-dev: ## Watch dev container status every 2s
	watch -n 2 '$(DC_DEV) ps'

watch-prod: ## Watch prod container status every 2s
	watch -n 2 '$(DC_PROD) ps'

top: ## Show top processes per dev container
	$(DC_DEV) top

top-prod: ## Show top processes per prod container
	$(DC_PROD) top

# ----------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------
clean-dev: ## ⚠️  down -v on dev (removes ALL volumes/data)
	$(DC_DEV) down -v
	@echo "✓ Development cleanup complete"

clean-prod: ## down on prod (keeps volumes!)
	$(DC_PROD) down
	@echo "✓ Production cleanup complete"

clean-all: ## ⚠️  Wipe dev + prod (DROPS ALL DATA)
	$(DC_DEV) down -v --rmi local
	$(DC_PROD) down -v
	@echo "✓ Complete cleanup done"

prune: ## ⚠️  docker system prune -af --volumes (system-wide)
	docker system prune -af --volumes
	@echo "✓ Docker system pruned"

# ----------------------------------------------------------------
# Testing & Quality (Backend)
# ----------------------------------------------------------------
test-backend: ## Run backend pytest
	$(DC_DEV) exec backend pytest

test-backend-cov: ## Run backend pytest with HTML coverage
	$(DC_DEV) exec backend pytest --cov=. --cov-report=html

lint-backend: ## Run backend linter (ruff check)
	$(DC_DEV) exec backend ruff check .

lint-backend-fix: ## ruff check --fix
	$(DC_DEV) exec backend ruff check --fix .

format-backend: ## ruff format
	$(DC_DEV) exec backend ruff format .

# ----------------------------------------------------------------
# Aliases
# ----------------------------------------------------------------
up: dev-up ## Alias for dev-up
down: dev-down ## Alias for dev-down
logs: dev-logs ## Alias for dev-logs
build: dev-build ## Alias for dev-build
