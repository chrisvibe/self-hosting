#!/bin/bash
# Template for creating new service setup scripts
# Copy this file and modify for your service

set -e

# Configuration - CHANGE THESE
SERVICE_NAME="yourservice"
SERVICE_REPO="git@github.com:username/service-repo.git"  # Use SSH URL for submodules
CONTAINER_NAME="yourservice"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVICE_DIR="$PROJECT_ROOT/services/$SERVICE_NAME"
OVERRIDE_FILE="$PROJECT_ROOT/overrides/${SERVICE_NAME}.override.yaml"

echo "Setting up $SERVICE_NAME service..."

# Check if already a submodule or needs initialization
if [ ! -d "$SERVICE_DIR" ] || [ ! -f "$SERVICE_DIR/.git" ]; then
    echo "Initializing $SERVICE_NAME submodule..."
    cd "$PROJECT_ROOT"
    
    # Add submodule if not already in .gitmodules
    if ! grep -q "services/$SERVICE_NAME" .gitmodules 2>/dev/null; then
        echo "Adding $SERVICE_NAME as submodule..."
        git submodule add "$SERVICE_REPO" "services/$SERVICE_NAME"
    else
        echo "Updating existing submodule..."
        git submodule update --init --recursive "services/$SERVICE_NAME"
    fi
    
    echo "✅ Submodule initialized"
else
    echo "$SERVICE_NAME submodule already exists"
fi

# Create symlink to override file if override exists
if [ -f "$OVERRIDE_FILE" ]; then
    if [ ! -f "$SERVICE_DIR/docker-compose.override.yaml" ]; then
        echo "Linking docker-compose.override.yaml..."
        ln -s "$OVERRIDE_FILE" "$SERVICE_DIR/docker-compose.override.yaml"
        echo "✅ Override linked"
    else
        echo "Override already exists"
    fi
else
    echo "⚠️  No override file found at $OVERRIDE_FILE"
    echo "Create one with: ./scripts/generate-override.sh $SERVICE_NAME $CONTAINER_NAME"
fi

# Copy env template if .env doesn't exist
if [ -f "$SERVICE_DIR/env_template" ] && [ ! -f "$SERVICE_DIR/.env" ]; then
    echo "Creating .env from template..."
    cp "$SERVICE_DIR/env_template" "$SERVICE_DIR/.env"
    chmod 600 "$SERVICE_DIR/.env"
    echo "⚠️  Please edit services/$SERVICE_NAME/.env with your configuration!"
elif [ ! -f "$SERVICE_DIR/env_template" ]; then
    echo "No env_template found, skipping .env creation"
else
    echo ".env already exists, skipping..."
fi

echo ""
echo "✅ $SERVICE_NAME service setup complete!"
echo ""
echo "Next steps:"
echo "1. cd services/$SERVICE_NAME"
echo "2. Edit .env if needed"
echo "3. Follow the service README for setup"
echo "4. docker compose up -d"
echo "5. Add Cloudflare route: $SERVICE_NAME.yourdomain.com → http://$CONTAINER_NAME:[port]"
