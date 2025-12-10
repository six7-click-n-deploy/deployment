#!/bin/bash

# ================================================================
# Trigger Deployment Task
# ================================================================
# Triggers a pending deployment task in the worker container

set -e

COMPOSE_FILE="docker-compose.dev.yml"

echo "🚀 Triggering deployment task..."
echo ""

# Run the Python script inside the worker container
docker-compose -f "$COMPOSE_FILE" exec worker python trigger_deployment.py "$@"

echo ""
echo "📊 View task status:"
echo "   - Flower Dashboard: http://localhost:5555"
echo "   - Worker Logs: docker-compose -f $COMPOSE_FILE logs -f worker"
