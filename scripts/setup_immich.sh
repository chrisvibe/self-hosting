#!/bin/bash
# Immich service setup script

set -e

# Configuration
SERVICE_NAME="immich"
CONTAINER_NAME="immich-server"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVICE_DIR="$PROJECT_ROOT/services/$SERVICE_NAME"
OVERRIDE_SOURCE="$PROJECT_ROOT/overrides/immich.override.yaml"
OVERRIDE_TARGET="$SERVICE_DIR/docker-compose.override.yaml"

echo "Setting up $SERVICE_NAME service..."

# Check if service directory exists
if [ ! -d "$SERVICE_DIR" ]; then
    echo "❌ Error: $SERVICE_DIR does not exist"
    echo "Please create the Immich service directory first"
    exit 1
fi

# Create symlink to override file if override exists
if [ -f "$OVERRIDE_SOURCE" ]; then
    if [ -L "$OVERRIDE_TARGET" ]; then
        echo "Override symlink already exists, removing old one..."
        rm "$OVERRIDE_TARGET"
    elif [ -f "$OVERRIDE_TARGET" ]; then
        echo "⚠️  Override file exists but is not a symlink"
        echo -n "Replace with symlink? (y/n): "
        read -r response
        if [ "$response" != "y" ]; then
            echo "Skipping override setup"
        else
            rm "$OVERRIDE_TARGET"
        fi
    fi
    
    if [ ! -e "$OVERRIDE_TARGET" ]; then
        echo "Linking docker-compose.override.yaml..."
        ln -s "$OVERRIDE_SOURCE" "$OVERRIDE_TARGET"
        echo "✅ Override linked"
    fi
else
    echo "⚠️  No override file found at $OVERRIDE_SOURCE"
    echo "Create one with: cp ~/immich.override.yaml $OVERRIDE_SOURCE"
fi

# Check if .env exists
if [ ! -f "$SERVICE_DIR/.env" ]; then
    echo "⚠️  No .env file found in $SERVICE_DIR"
    echo "You'll need to configure IMMICH_SERVER_URL in .env"
    echo ""
    echo "Add this to your .env file:"
    echo "IMMICH_SERVER_URL=https://photos.yourdomain.com  # Change to your actual domain"
else
    # Check if IMMICH_SERVER_URL is set
    if ! grep -q "^IMMICH_SERVER_URL=" "$SERVICE_DIR/.env"; then
        echo ""
        echo "⚠️  Add IMMICH_SERVER_URL to your .env file:"
        echo "IMMICH_SERVER_URL=https://photos.yourdomain.com  # Change to your actual domain"
    fi
fi

echo ""
echo "✅ $SERVICE_NAME service setup complete!"
echo ""
echo "Next steps:"
echo "1. Ensure IMMICH_SERVER_URL is set in services/$SERVICE_NAME/.env"
echo "   Example: IMMICH_SERVER_URL=https://photos.yourdomain.com"
echo ""
echo "2. Restart Immich:"
echo "   cd services/$SERVICE_NAME"
echo "   docker compose down && docker compose up -d"
echo ""
echo "3. Add Cloudflare Tunnel route:"
echo "   Subdomain: photos (or your preference)"
echo "   Domain: yourdomain.com"
echo "   Service: http://immich-server:2283"
echo ""
echo "4. For local access, use: http://192.168.1.42:2283"
echo "   (Immich validates hostnames, so use IP locally)"
