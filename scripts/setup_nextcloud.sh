#!/bin/bash
# Setup Nextcloud service
# Place in: ~/self-hosting/scripts/setup-nextcloud.sh

set -e

SERVICE_NAME="nextcloud"
SERVICE_REPO="git@github.com:chrisvibe/nextcloud.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVICE_DIR="$PROJECT_ROOT/services/$SERVICE_NAME"
OVERRIDE_FILE="$PROJECT_ROOT/overrides/${SERVICE_NAME}.override.yaml"

echo "Setting up $SERVICE_NAME..."

# Add/update submodule
if [ ! -d "$SERVICE_DIR/.git" ]; then
    cd "$PROJECT_ROOT"
    if ! grep -q "services/$SERVICE_NAME" .gitmodules 2>/dev/null; then
        git submodule add "$SERVICE_REPO" "services/$SERVICE_NAME"
    else
        git submodule update --init "services/$SERVICE_NAME"
    fi
    echo "✅ Submodule initialized"
else
    echo "Submodule exists"
fi

# Link override
if [ ! -f "$SERVICE_DIR/docker-compose.override.yaml" ]; then
    cd "$SERVICE_DIR"
    ln -sf "../../overrides/${SERVICE_NAME}.override.yaml" docker-compose.override.yaml
    echo "✅ Override linked"
fi

# Create .env
if [ ! -f "$SERVICE_DIR/.env" ]; then
    cp "$SERVICE_DIR/env_template" "$SERVICE_DIR/.env"
    chmod 600 "$SERVICE_DIR/.env"
    echo "⚠️  Edit services/$SERVICE_NAME/.env with secure passwords!"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. cd services/$SERVICE_NAME"
echo "  2. nano .env  # Set domain and CHANGE DEFAULT PASSWORDS!"
echo "  3. docker compose up -d"
echo "  4. Wait 1-2 minutes for initialization"
echo "  5. Configure Cloudflare route: nextcloud.yourdomain.com → http://nextcloud:80"
echo "  6. Access https://nextcloud.yourdomain.com and complete setup"
echo ""
echo "Optional: Mount external drive"
echo "  Add to docker-compose.override.yaml:"
echo "    services:"
echo "      nextcloud:"
echo "        volumes:"
echo "          - /media/external/drive:/external-data"
