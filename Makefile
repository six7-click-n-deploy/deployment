# ================================================================
# Makefile for Multi-Repo Deployment
# Manages frontend, backend, worker services
# ================================================================

.PHONY: help build up down logs shell migrate test clean

# Default target
.DEFAULT_GOAL := help

# ----------------------------------------------------------------
# Help
# ----------------------------------------------------------------
help: ## Show this help message
	@echo "🚀 Deployment - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Services: frontend, backend, worker, postgres, redis"
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

secret: ## Generate a new secret key
	@python3 -c "import secrets; print('SECRET_KEY=' + secrets.token_hex(32))"

# ----------------------------------------------------------------
# Development Environment
# ----------------------------------------------------------------
dev-up: ## Start development environment
	docker compose -f docker-compose.dev.yml up -d
	@echo ""
	@echo "✓ Development environment started"
	@echo "  Frontend:  http://localhost:5173"
	@echo "  Backend:   http://localhost:8000"
	@echo "  API Docs:  http://localhost:8000/docs"
	@echo "  pgAdmin:   http://localhost:5050 (admin@admin.com / admin)"
	@echo ""

dev-down: ## Stop development environment
	docker compose -f docker-compose.dev.yml down

dev-restart: ## Restart development environment
	docker compose -f docker-compose.dev.yml restart

dev-logs: ## View development logs (all services)
	docker compose -f docker-compose.dev.yml logs -f

dev-logs-backend: ## View backend logs only
	docker compose -f docker-compose.dev.yml logs -f backend

dev-logs-frontend: ## View frontend logs only
	docker compose -f docker-compose.dev.yml logs -f frontend

dev-logs-worker: ## View worker logs only
	docker compose -f docker-compose.dev.yml logs -f worker

dev-build: ## Build development images
	docker compose -f docker-compose.dev.yml build

dev-build-backend: ## Build backend dev image only
	docker compose -f docker-compose.dev.yml build backend

dev-build-frontend: ## Build frontend dev image only
	docker compose -f docker-compose.dev.yml build frontend

dev-build-worker: ## Build worker dev image only
	docker compose -f docker-compose.dev.yml build worker

dev-rebuild: ## Rebuild and restart dev environment
	docker compose -f docker-compose.dev.yml down
	docker compose -f docker-compose.dev.yml build --no-cache
	docker compose -f docker-compose.dev.yml up -d

dev-ps: ## List development containers
	docker compose -f docker-compose.dev.yml ps

# ----------------------------------------------------------------
# Production Environment
# ----------------------------------------------------------------
prod-up: ## Start production environment
	docker compose -f docker-compose.prod.yml up -d
	@echo "✓ Production environment started"

prod-down: ## Stop production environment
	docker compose -f docker-compose.prod.yml down

prod-restart: ## Restart production environment
	docker compose -f docker-compose.prod.yml restart

prod-logs: ## View production logs (all services)
	docker compose -f docker-compose.prod.yml logs -f

prod-logs-backend: ## View backend logs only
	docker compose -f docker-compose.prod.yml logs -f backend

prod-logs-frontend: ## View frontend logs only
	docker compose -f docker-compose.prod.yml logs -f frontend

prod-logs-worker: ## View worker logs only
	docker compose -f docker-compose.prod.yml logs -f worker

prod-pull: ## Pull latest production images
	docker compose -f docker-compose.prod.yml pull

prod-ps: ## List production containers
	docker compose -f docker-compose.prod.yml ps

prod-update: ## Update production (pull + restart)
	docker compose -f docker-compose.prod.yml pull
	docker compose -f docker-compose.prod.yml up -d
	@echo "✓ Production environment updated"

# ----------------------------------------------------------------
# Shell Access
# ----------------------------------------------------------------
shell-backend: ## Open shell in backend container (dev)
	docker compose -f docker-compose.dev.yml exec backend bash

shell-backend-prod: ## Open shell in backend container (prod)
	docker compose -f docker-compose.prod.yml exec backend bash

shell-worker: ## Open shell in worker container (dev)
	docker compose -f docker-compose.dev.yml exec worker bash

shell-worker-prod: ## Open shell in worker container (prod)
	docker compose -f docker-compose.prod.yml exec worker bash

shell-frontend: ## Open shell in frontend container (dev)
	docker compose -f docker-compose.dev.yml exec frontend sh

shell-db: ## Open PostgreSQL shell (dev)
	docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d backend_dev

shell-db-prod: ## Open PostgreSQL shell (prod)
	docker compose -f docker-compose.prod.yml exec postgres psql -U postgres

shell-redis: ## Open Redis CLI (dev)
	docker compose -f docker-compose.dev.yml exec redis redis-cli

shell-redis-prod: ## Open Redis CLI (prod)
	docker compose -f docker-compose.prod.yml exec redis redis-cli

# ----------------------------------------------------------------
# Database Migrations
# ----------------------------------------------------------------
migrate-dev: ## Run database migrations (dev)
	docker compose -f docker-compose.dev.yml exec backend poetry run alembic upgrade head

migrate-prod: ## Run database migrations (prod)
	docker compose -f docker-compose.prod.yml exec backend alembic upgrade head

migration-create: ## Create new migration (dev, usage: make migration-create MSG="message")
	@if [ -z "$(MSG)" ]; then \
		echo "Error: Please provide a message. Usage: make migration-create MSG='Your message'"; \
		exit 1; \
	fi
	docker compose -f docker-compose.dev.yml exec backend alembic revision --autogenerate -m "$(MSG)"

migration-history: ## Show migration history (dev)
	docker compose -f docker-compose.dev.yml exec backend alembic history

migration-current: ## Show current migration (dev)
	docker compose -f docker-compose.dev.yml exec backend alembic current

migration-downgrade: ## Downgrade one migration (dev)
	docker compose -f docker-compose.dev.yml exec backend alembic downgrade -1

# ----------------------------------------------------------------
# Database Management
# ----------------------------------------------------------------
db-backup: ## Backup database (prod)
	docker compose -f docker-compose.prod.yml exec postgres pg_dump -U postgres > backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "✓ Database backed up"

db-restore: ## Restore database (prod, usage: make db-restore FILE=backup.sql)
	@if [ -z "$(FILE)" ]; then \
		echo "Error: Please provide a backup file. Usage: make db-restore FILE=backup.sql"; \
		exit 1; \
	fi
	docker compose -f docker-compose.prod.yml exec -T postgres psql -U postgres < $(FILE)

db-reset-dev: ## Reset development database (⚠️ WARNING: Deletes all data!)
	@echo "⚠️  WARNING: This will delete all development database data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose -f docker-compose.dev.yml down -v; \
		docker compose -f docker-compose.dev.yml up -d postgres redis; \
		sleep 5; \
		docker compose -f docker-compose.dev.yml up -d; \
		sleep 3; \
		$(MAKE) migrate-dev; \
		echo "✓ Development database reset complete"; \
	fi

# ----------------------------------------------------------------
# Health Checks
# ----------------------------------------------------------------
health: ## Check all service health (dev)
	@echo "🏥 Checking service health..."
	@echo ""
	@echo "Backend:"
	@curl -sf http://localhost:8000/health || echo "  ❌ Backend not healthy"
	@echo ""
	@echo "Frontend:"
	@curl -sf http://localhost:3000 > /dev/null && echo "  ✓ Frontend healthy" || echo "  ❌ Frontend not healthy"
	@echo ""

health-prod: ## Check all service health (prod)
	@echo "🏥 Checking production service health..."
	@echo ""
	@docker compose -f docker-compose.prod.yml ps

status: ## Show container status (dev)
	docker compose -f docker-compose.dev.yml ps

status-prod: ## Show container status (prod)
	docker compose -f docker-compose.prod.yml ps

# ----------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------
stats: ## Show container resource usage (dev)
	docker stats

watch-dev: ## Watch development logs in real-time
	watch -n 2 'docker compose -f docker-compose.dev.yml ps'

watch-prod: ## Watch production logs in real-time
	watch -n 2 'docker compose -f docker-compose.prod.yml ps'

top: ## Show top processes in containers (dev)
	docker compose -f docker-compose.dev.yml top

top-prod: ## Show top processes in containers (prod)
	docker compose -f docker-compose.prod.yml top

# ----------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------
clean-dev: ## Remove all dev containers and volumes
	docker compose -f docker-compose.dev.yml down -v
	@echo "✓ Development cleanup complete"

clean-prod: ## Remove all prod containers (keeps volumes!)
	docker compose -f docker-compose.prod.yml down
	@echo "✓ Production cleanup complete"

clean-all: ## Remove everything (⚠️ WARNING: Deletes all data!)
	docker compose -f docker-compose.dev.yml down -v --rmi local
	docker compose -f docker-compose.prod.yml down -v
	@echo "✓ Complete cleanup done"

prune: ## Remove unused Docker resources
	docker system prune -af --volumes
	@echo "✓ Docker system pruned"

# ----------------------------------------------------------------
# Testing & Quality (Development)
# ----------------------------------------------------------------
test-backend: ## Run backend tests
	docker compose -f docker-compose.dev.yml exec backend pytest

test-backend-cov: ## Run backend tests with coverage
	docker compose -f docker-compose.dev.yml exec backend pytest --cov=. --cov-report=html

lint-backend: ## Run backend linter
	docker compose -f docker-compose.dev.yml exec backend ruff check .

lint-backend-fix: ## Fix backend linting issues
	docker compose -f docker-compose.dev.yml exec backend ruff check --fix .

format-backend: ## Format backend code
	docker compose -f docker-compose.dev.yml exec backend ruff format .

# ----------------------------------------------------------------
# Utilities
# ----------------------------------------------------------------
restart-backend: ## Restart backend service (dev)
	docker compose -f docker-compose.dev.yml restart backend

restart-frontend: ## Restart frontend service (dev)
	docker compose -f docker-compose.dev.yml restart frontend

restart-worker: ## Restart worker service (dev)
	docker compose -f docker-compose.dev.yml restart worker

restart-backend-prod: ## Restart backend service (prod)
	docker compose -f docker-compose.prod.yml restart backend

restart-frontend-prod: ## Restart frontend service (prod)
	docker compose -f docker-compose.prod.yml restart frontend

restart-worker-prod: ## Restart worker service (prod)
	docker compose -f docker-compose.prod.yml restart worker

# ----------------------------------------------------------------
# Quick Commands
# ----------------------------------------------------------------
up: dev-up ## Alias for dev-up
down: dev-down ## Alias for dev-down
logs: dev-logs ## Alias for dev-logs
build: dev-build ## Alias for dev-build
