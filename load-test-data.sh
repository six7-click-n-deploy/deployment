#!/bin/bash
# Load test data into the database

set -e

echo "🗄️  Loading test data into database..."

# Database connection details
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-backend_dev}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Check if running in Docker
if command -v docker &> /dev/null && docker ps | grep -q postgres-dev; then
    echo "📦 Running in Docker - using docker exec..."
    docker exec -i postgres-dev psql -U "$DB_USER" -d "$DB_NAME" < test-data.sql
else
    echo "💻 Running locally - using psql..."
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f test-data.sql
fi

echo ""
echo "✅ Test data loaded successfully!"
echo ""
echo "📊 Created:"
echo "  - User: testuser (password: test123)"
echo "  - App: Simple Web Server"
echo "  - Deployment: Simple Web Server - Test Deployment (status: pending)"
echo ""
echo "🚀 Next steps:"
echo "  1. Check Flower dashboard: http://localhost:5555"
echo "  2. Manually trigger the deployment task or use the API"
echo "  3. Watch the deployment in Flower!"
echo ""
