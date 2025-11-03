#!/bin/bash

set -e

# Load environment
set -a
source ../.env
set +a

mkdir -p conf.d

# Generate nginx.conf with actual IPs
echo "Generating nginx.conf for $DOMAIN..."

# Start with the template
cp nginx.conf.template conf.d/nginx.conf

# Replace server name
sed -i "s/DOMAIN/$DOMAIN/g" conf.d/nginx.conf

echo "✅ Generated nginx.conf"
