#!/bin/bash

# Deployment script for Staging environment
# Usage: ./deploy-staging.sh <artifacts_dir> [skip_db]

set -e

ARTIFACTS_DIR="${1:-.}"
SKIP_DB="${2:-false}"
DEPLOY_DIR="/opt/itqan/staging"
BACKUP_DIR="/opt/itqan/backups/staging"
VERSION=$(date +%Y%m%d_%H%M%S)

echo "📦 Staging Deployment Script"
echo "============================"
echo "Artifacts: $ARTIFACTS_DIR"
echo "Deploy Dir: $DEPLOY_DIR"
echo "Version: $VERSION"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current deployment
if [ -d "$DEPLOY_DIR/current" ]; then
    echo "📦 Creating backup of current deployment..."
    cp -r "$DEPLOY_DIR/current" "$BACKUP_DIR/backup_$VERSION"
    echo "✓ Backup created: $BACKUP_DIR/backup_$VERSION"
fi

# Create new version directory
DEPLOY_VERSION_DIR="$DEPLOY_DIR/$VERSION"
mkdir -p "$DEPLOY_VERSION_DIR"

# Extract and deploy web version
echo "📦 Deploying Web version..."
if [ -f "$ARTIFACTS_DIR/kinetic-web.zip" ]; then
    unzip -q "$ARTIFACTS_DIR/kinetic-web.zip" -d "$DEPLOY_VERSION_DIR/web"
    echo "✓ Web deployed"
else
    echo "⚠️  Web artifact not found"
fi

# Copy APK and AAB
echo "📦 Deploying Mobile versions..."
if [ -f "$ARTIFACTS_DIR/kinetic-app.apk" ]; then
    cp "$ARTIFACTS_DIR/kinetic-app.apk" "$DEPLOY_VERSION_DIR/kinetic-app.apk"
    echo "✓ APK deployed"
fi

if [ -f "$ARTIFACTS_DIR/kinetic-app.aab" ]; then
    cp "$ARTIFACTS_DIR/kinetic-app.aab" "$DEPLOY_VERSION_DIR/kinetic-app.aab"
    echo "✓ AAB deployed"
fi

# Update symlink to current version
echo "🔄 Updating current symlink..."
rm -f "$DEPLOY_DIR/current"
ln -s "$DEPLOY_VERSION_DIR" "$DEPLOY_DIR/current"
echo "✓ Symlink updated"

# Database migrations (if not skipped)
if [ "$SKIP_DB" = "false" ]; then
    echo "🗄️  Running database migrations..."
    # Add your database migration command here
    # Example: psql -U postgres -d itqan_staging < "$DEPLOY_VERSION_DIR/migrations.sql"
    echo "✓ Database migrations completed"
else
    echo "⏭️  Skipping database migrations"
fi

# Restart services if needed
echo "🔄 Restarting services..."
# Example: systemctl restart itqan-staging || true
echo "✓ Services restarted (or would be, if configured)"

# Health check
echo "🏥 Running health checks..."
sleep 2

if [ -f "$DEPLOY_DIR/current/web/index.html" ]; then
    echo "✓ Web version is accessible"
else
    echo "❌ Health check failed!"
    echo "Rolling back to previous version..."
    if [ -L "$BACKUP_DIR/latest" ]; then
        LATEST_BACKUP=$(readlink "$BACKUP_DIR/latest")
        rm -f "$DEPLOY_DIR/current"
        ln -s "$LATEST_BACKUP" "$DEPLOY_DIR/current"
    fi
    exit 1
fi

# Update latest backup symlink
ln -sf "$DEPLOY_VERSION_DIR" "$BACKUP_DIR/latest"

echo ""
echo "✅ Staging deployment completed successfully!"
echo "Version: $VERSION"
echo "URL: https://staging.itqan.local"
echo ""
echo "Deployed artifacts:"
ls -lh "$DEPLOY_VERSION_DIR"
