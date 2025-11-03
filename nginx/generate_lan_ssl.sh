#!/bin/bash

# Generate self-signed SSL certificate for LAN proxy
# Used for local HTTPS access to services

set -e

# Load environment for server name
set -a
source ../.env
set +a

SSL_DIR="ssl"
mkdir -p "$SSL_DIR"

DOMAIN="tubiformis.work"

echo "Generating self-signed SSL certificate for *.$DOMAIN..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/key.pem" \
    -out "$SSL_DIR/cert.pem" \
    -subj "/CN=*.$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN,IP:${LOCAL_IP:-192.168.1.42}" \
    2>/dev/null

chmod 600 "$SSL_DIR/key.pem"
chmod 644 "$SSL_DIR/cert.pem"

echo "SSL certificate generated in $SSL_DIR/"
echo "This certificate is for LAN HTTPS access only"
echo ""
echo "You'll need to accept the certificate warning once per device/browser"
