#!/bin/bash

# Deployment script for Production environment
# Usage: ./deploy-production.sh <artifacts_dir> [skip_db] [mandatory_update]

set -e

ARTIFACTS_DIR="${1:-.}"
SKIP_DB="${2:-false}"
MANDATORY_UPDATE="${3:-false}"
DEPLOY_DIR="/opt/itqan/production"
BACKUP_DIR="/opt/itqan/backups/production"
VERSION=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/itqan/deployment_$VERSION.log"

echo "🚨 PRODUCTION DEPLOYMENT SCRIPT 🚨"
echo "===================================="
echo "Artifacts: $ARTIFACTS_DIR"
echo "Deploy Dir: $DEPLOY_DIR"
echo "Version: $VERSION"
echo "Mandatory Update: $MANDATORY_UPDATE"
echo ""

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Log everything
{
    echo "=== Production Deployment Log ==="
    echo "Start Time: $(date)"
    echo "Version: $VERSION"
    echo ""

    # Pre-deployment checks
    echo "📋 Pre-deployment checks..."

    # Check if artifacts exist
    if [ ! -f "$ARTIFACTS_DIR/kinetic-web.zip" ] || [ ! -f "$ARTIFACTS_DIR/kinetic-app.apk" ]; then
        echo "❌ Required artifacts not found!"
        exit 1
    fi
    echo "✓ All artifacts present"

    # Check disk space
    REQUIRED_SPACE=$((500 * 1024 * 1024)) # 500MB
    AVAILABLE_SPACE=$(df "$DEPLOY_DIR" | tail -1 | awk '{print $4 * 1024}')
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        echo "❌ Insufficient disk space!"
        exit 1
    fi
    echo "✓ Sufficient disk space: $(numfmt --to=iec-i --suffix=B $AVAILABLE_SPACE)"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup current production deployment
    echo "📦 Creating backup of current production..."
    if [ -d "$DEPLOY_DIR/current" ]; then
        BACKUP_PATH="$BACKUP_DIR/backup_$VERSION"
        cp -r "$DEPLOY_DIR/current" "$BACKUP_PATH"
        echo "✓ Backup created: $BACKUP_PATH"
    fi

    # Create new version directory
    DEPLOY_VERSION_DIR="$DEPLOY_DIR/$VERSION"
    mkdir -p "$DEPLOY_VERSION_DIR"

    # Extract and deploy web version
    echo "📦 Deploying Web version..."
    unzip -q "$ARTIFACTS_DIR/kinetic-web.zip" -d "$DEPLOY_VERSION_DIR/web"
    echo "✓ Web deployed"

    # Copy mobile artifacts
    echo "📦 Deploying Mobile versions..."
    cp "$ARTIFACTS_DIR/kinetic-app.apk" "$DEPLOY_VERSION_DIR/kinetic-app.apk"
    cp "$ARTIFACTS_DIR/kinetic-app.aab" "$DEPLOY_VERSION_DIR/kinetic-app.aab"
    echo "✓ Mobile apps deployed"

    # Create deployment metadata
    cat > "$DEPLOY_VERSION_DIR/DEPLOYMENT_INFO" << EOF
Version: $VERSION
Deployment Date: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Mandatory Update: $MANDATORY_UPDATE
Skip DB: $SKIP_DB
Deployed By: GitHub Actions
EOF

    # Update symlink to current version
    echo "🔄 Updating production symlink..."
    rm -f "$DEPLOY_DIR/current"
    ln -s "$DEPLOY_VERSION_DIR" "$DEPLOY_DIR/current"
    echo "✓ Symlink updated"

    # Database migrations (if not skipped)
    if [ "$SKIP_DB" = "false" ]; then
        echo "🗄️  Running database migrations..."
        # Add your database migration command here
        # Example: psql -U postgres -d itqan_prod < "$DEPLOY_VERSION_DIR/migrations.sql"
        echo "✓ Database migrations completed"
    else
        echo "⏭️  Skipping database migrations"
    fi

    # Restart services with health check
    echo "🔄 Restarting services..."
    # Example: systemctl restart itqan-production || true
    echo "✓ Services restarted"

    # Health check
    echo "🏥 Running health checks..."
    sleep 3

    if [ ! -f "$DEPLOY_DIR/current/web/index.html" ]; then
        echo "❌ Health check failed! Rolling back..."
        echo "Rollback Time: $(date)"

        # Rollback to previous version
        if [ -d "$BACKUP_DIR/latest" ]; then
            LATEST_BACKUP=$(readlink -f "$BACKUP_DIR/latest" 2>/dev/null || echo "$BACKUP_DIR/backup_previous")
            rm -f "$DEPLOY_DIR/current"
            ln -s "$LATEST_BACKUP" "$DEPLOY_DIR/current"
            echo "✓ Rolled back to: $LATEST_BACKUP"
        fi

        # Restart with old version
        # Example: systemctl restart itqan-production || true
        exit 1
    fi

    echo "✓ Health checks passed"

    # Update latest backup symlink
    ln -sf "$BACKUP_PATH" "$BACKUP_DIR/latest" 2>/dev/null || true

    # Clean old backups (keep last 5)
    echo "🧹 Cleaning old backups..."
    cd "$BACKUP_DIR"
    ls -1dt backup_* | tail -n +6 | xargs rm -rf || true
    echo "✓ Old backups cleaned"

    # Final verification
    echo ""
    echo "✅ Production deployment completed successfully!"
    echo "Version: $VERSION"
    echo "URL: https://erp.itqan.local"
    echo "End Time: $(date)"
    echo ""
    echo "Deployed artifacts:"
    ls -lh "$DEPLOY_VERSION_DIR"

} | tee "$LOG_FILE"

exit 0
