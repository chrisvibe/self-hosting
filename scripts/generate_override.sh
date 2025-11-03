#!/bin/bash
# Generate a docker-compose override file for a service

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <service-name> <container-name>"
    echo ""
    echo "Example: $0 matrix matrix-nginx"
    echo "Example: $0 syncthing syncthing"
    echo ""
    echo "This creates overrides/<service-name>.override.yaml"
    exit 1
fi

SERVICE_NAME="$1"
CONTAINER_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OVERRIDE_DIR="$PROJECT_ROOT/overrides"
OVERRIDE_FILE="$OVERRIDE_DIR/${SERVICE_NAME}.override.yaml"

# Create overrides directory if it doesn't exist
mkdir -p "$OVERRIDE_DIR"

# Check if override already exists
if [ -f "$OVERRIDE_FILE" ]; then
    echo "⚠️  Override file already exists: $OVERRIDE_FILE"
    echo -n "Overwrite? (y/n): "
    read -r response
    if [ "$response" != "y" ]; then
        echo "Cancelled"
        exit 0
    fi
fi

# Generate override file
cat > "$OVERRIDE_FILE" <<EOF
# $SERVICE_NAME service override for self-hosting infrastructure
# This connects the service to the shared tunnel network

services:
  # Change the service name below if your docker-compose.yaml uses a different name
  ${CONTAINER_NAME##*-}:  # Remove prefix for service name
    container_name: $CONTAINER_NAME
    networks:
      - default  # Internal service network
      - web      # External tunnel network

networks:
  web:
    external: true
    name: web
EOF

echo "✅ Created override file: $OVERRIDE_FILE"
echo ""
echo "Review and edit if needed. The service name might need adjustment."
echo ""
echo "Next: Run ./scripts/setup-${SERVICE_NAME}.sh to apply it"
