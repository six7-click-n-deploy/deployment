# Deployment Repository

Central orchestration for all services (frontend, backend, worker).

## 📁 Structure

```
deployment/
├── docker-compose.dev.yml      # Development environment
├── docker-compose.prod.yml     # Production environment
├── Makefile                    # Orchestration commands
├── .env.example               # Environment template
├── .env                       # Your environment (not in git)
└── README.md                  # This file
```

## 🚀 Quick Start

### First Time Setup

```bash
# 1. Clone all repositories
git clone https://github.com/six7-click-n-deploy/frontend.git
git clone https://github.com/six7-click-n-deploy/backend.git
git clone https://github.com/six7-click-n-deploy/worker.git
git clone https://github.com/six7-click-n-deploy/deployment.git

# Expected structure:
# /path/to/project/
#   ├── frontend/
#   ├── backend/
#   ├── worker/
#   └── deployment/   <- You are here

# 2. Create environment file
cd deployment
make env

# 3. Edit .env with your values
nano .env

# 4. Generate secret key
make secret  # Copy output to .env

# 5. Start development environment
make dev-up

# 6. Run initial migrations
make migrate-dev
```

### Access Services

```
Frontend:  http://localhost:3000
Backend:   http://localhost:8000
API Docs:  http://localhost:8000/docs
pgAdmin:   http://localhost:5050 (admin@admin.com / admin)
```

## 🔧 Development Workflow

### Daily Commands

```bash
# Start everything
make dev-up

# View logs
make dev-logs              # All services
make dev-logs-backend      # Backend only
make dev-logs-frontend     # Frontend only
make dev-logs-worker       # Worker only

# Restart a service
make restart-backend
make restart-frontend
make restart-worker

# Stop everything
make dev-down
```

### Code Changes

**Hot Reload is enabled!** Just edit code in:
- `../frontend/` - Frontend auto-reloads
- `../backend/` - Backend auto-reloads
- `../worker/` - Worker auto-reloads

No need to rebuild containers for code changes.

### Database Changes

```bash
# Create migration (after changing models in backend)
make migration-create MSG="Add user avatar field"

# Apply migrations
make migrate-dev

# View migration history
make migration-history

# Rollback one migration
make migration-downgrade
```

### Rebuilding

```bash
# Rebuild specific service
make dev-build-backend
make dev-build-frontend
make dev-build-worker

# Rebuild everything
make dev-build

# Full clean rebuild
make dev-rebuild
```

## 🚀 Production Deployment

### Prerequisites

1. Images are built and pushed to GitHub Container Registry
2. `.env` file is configured with production values
3. Server has Docker and Docker Compose installed

### Deploy

```bash
# 1. Pull latest images
make prod-pull

# 2. Start production environment
make prod-up

# 3. Check status
make status-prod

# 4. View logs
make prod-logs
```

### Update Production

```bash
# Pull latest images and restart
make prod-update

# Or manually:
make prod-pull
make prod-down
make prod-up
```

### Production Monitoring

```bash
# Check health
make health-prod

# View logs
make prod-logs
make prod-logs-backend
make prod-logs-frontend
make prod-logs-worker

# Container stats
make stats

# Watch status
make watch-prod
```

## 🗄️ Database Management

### Backup & Restore

```bash
# Backup production database
make db-backup

# Restore from backup
make db-restore FILE=backup_20231208_120000.sql
```

### Reset Development DB

```bash
# ⚠️ WARNING: Deletes all data!
make db-reset-dev
```

## 🐚 Shell Access

```bash
# Backend
make shell-backend          # Dev
make shell-backend-prod     # Prod

# Worker
make shell-worker           # Dev
make shell-worker-prod      # Prod

# Frontend
make shell-frontend         # Dev

# Database
make shell-db               # Dev
make shell-db-prod          # Prod

# Redis
make shell-redis            # Dev
make shell-redis-prod       # Prod
```

## 🧪 Testing & Code Quality

```bash
# Run backend tests
make test-backend

# With coverage
make test-backend-cov

# Linting
make lint-backend
make lint-backend-fix

# Formatting
make format-backend
```

## 📊 Architecture

### Development (docker-compose.dev.yml)
- **Build**: Local builds from `Dockerfile.dev` in each repo
- **Source**: Mounted from `../service/` directories
- **Reload**: Hot reload enabled
- **Database**: PostgreSQL with pgAdmin UI
- **Networks**: Separate isolated networks

### Production (docker-compose.prod.yml)
- **Images**: Pulled from `ghcr.io/six7-click-n-deploy/`
- **Versions**: Controlled via `.env` (`BACKEND_VERSION`, etc.)
- **Migrations**: Separate init container
- **Resources**: CPU/Memory limits set
- **Logging**: JSON file driver with rotation
- **Networks**: Separate isolated networks

### Network Topology

```
┌─────────────┐
│  Frontend   │
└──────┬──────┘
       │ frontend-network
┌──────▼──────┐
│  Backend    │
└──┬────────┬─┘
   │        │
   │ backend-network    worker-network
   │        │           │
┌──▼────┐ ┌─▼───────────▼─┐
│Postgres│ │     Worker    │
└────────┘ └───────────────┘
┌──────────┐
│  Redis   │ (shared: backend + worker)
└──────────┘
```

## 📋 Available Commands

Run `make help` to see all available commands:

```bash
make help
```

### Quick Reference

| Command | Description |
|---------|-------------|
| `make dev-up` | Start development |
| `make dev-down` | Stop development |
| `make dev-logs` | View logs |
| `make prod-up` | Start production |
| `make prod-pull` | Pull latest images |
| `make prod-update` | Update production |
| `make migrate-dev` | Run migrations |
| `make shell-backend` | Backend shell |
| `make health` | Check service health |

## 🔐 Environment Variables

See `.env.example` for all available variables.

### Required Variables

```bash
SECRET_KEY=<generate-with-make-secret>
DB_PASSWORD=<secure-password>
CORS_ORIGINS=https://yourdomain.com
```

### Generate Secret Key

```bash
make secret
# Copy output to .env
```

## 🐛 Troubleshooting

### Services Won't Start

```bash
# Check status
make status

# View logs
make dev-logs

# Check specific service
make dev-logs-backend
```

### Port Already in Use

Edit `.env` and change ports:
```bash
FRONTEND_PORT=3001
BACKEND_PORT=8001
```

### Database Connection Issues

```bash
# Check if postgres is running
make shell-db

# Reset database
make db-reset-dev
```

### Clean Everything and Start Fresh

```bash
# ⚠️ WARNING: Deletes all data!
make clean-dev
make dev-up
make migrate-dev
```

## 📚 Additional Documentation

- Backend: `../backend/README.md`
- Frontend: `../frontend/README.md`
- Worker: `../worker/README.md`
- Migrations: `../backend/MIGRATIONS.md`
- Docker: `../backend/DOCKER.md`

## 🆘 Support

For issues:
- Backend: https://github.com/six7-click-n-deploy/backend/issues
- Frontend: https://github.com/six7-click-n-deploy/frontend/issues
- Worker: https://github.com/six7-click-n-deploy/worker/issues
- Deployment: https://github.com/six7-click-n-deploy/deployment/issues
