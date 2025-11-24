# Self-Hosting Infrastructure
Personal self-hosted services infrastructure using Cloudflare Tunnel.

# install
git clone --recursive git@github.com:chrisvibe/self-hosting.git

## Architecture

```
Internet → Cloudflare Tunnel → Docker Network → Services
                                  (web)          ├─ Matrix
                                                 ├─ Syncthing
                                                 └─ ...
```

## Project Structure example

```
self-hosting/
├── docker-compose.yaml          # Cloudflare tunnel
├── env_template / .env          # Tunnel token
├── overrides/                   # Service network overrides
│   └── matrix.override.yaml
├── scripts/                     # Setup scripts
│   └── setup-matrix.sh
└── services/                    # Cloned service repos (gitignored)
    └── matrix/                  # Created by setup script
```

## Initial Setup

### 1. Create Cloudflare Tunnel

1. Log into Cloudflare Dashboard
2. Go to **Zero Trust** → **Networks** → **Tunnels**
3. Create a new tunnel (choose Docker connector)
4. Copy the tunnel token

### 2. Configure Environment

```bash
cp env_template .env
```

Edit `.env` and add your tunnel token:
```bash
CLOUDFLARE_TUNNEL_TOKEN='your_token_here'
```

### 3. Create Shared Network

```bash
docker network create web
```

### 4. Start Tunnel

```bash
docker compose up -d
```

The tunnel is now running and waiting for service configurations.

## Adding Services

### Matrix Server

1. **Run setup script:**
   ```bash
   ./scripts/setup-matrix.sh
   ```

   This will:
   - Clone the matrix-server repository
   - Symlink the network override
   - Create initial .env file

2. **Configure Matrix:**
   ```bash
   cd services/matrix
   # Edit .env with your domain and passwords
   nano .env
   ```

3. **Follow Matrix setup:**
   Follow the instructions in `services/matrix/README.md` for initial configuration:
   - Generate Synapse config
   - Configure PostgreSQL
   - Generate nginx and Element configs

4. **Start Matrix:**
   ```bash
   docker compose up -d
   ```

5. **Configure Cloudflare routes:**
   
   In Cloudflare Dashboard → Zero Trust → Networks → Tunnels → [Your Tunnel] → Public Hostname:

   **Route 1 - Client traffic:**
   - Subdomain: `matrix`
   - Domain: `yourdomain.com`
   - Service: `http://matrix-nginx:80`

   **Route 2 - Federation:**
   - Subdomain: `matrix`
   - Domain: `yourdomain.com`
   - Path: `/_matrix/federation/*`
   - Service: `https://matrix-nginx:8448`
   - Additional settings → TLS → Enable "No TLS Verify"

   **Route 3 - Federation keys:**
   - Subdomain: `matrix`
   - Domain: `yourdomain.com`
   - Path: `/_matrix/key/*`
   - Service: `https://matrix-nginx:8448`
   - Additional settings → TLS → Enable "No TLS Verify"

### Other Services

For each new service:

1. Create override file in `overrides/`
2. Create setup script in `scripts/`
3. Run setup script
4. Configure service
5. Add Cloudflare route

## Network Architecture

- **web network**: Shared bridge network that all services and the tunnel join
- Each service can also have internal networks for inter-service communication
- Tunnel → web network → service nginx/proxy → internal service network

## Updating Services

### Update Matrix
```bash
cd services/matrix
git pull
docker compose pull
docker compose up -d
```

## Backup

Each service should handle its own backups. For Matrix:

```bash
cd services/matrix
./admin_tools/backup.sh
```

## Troubleshooting

### Service not accessible from internet
1. Check tunnel is running: `docker compose ps`
2. Verify Cloudflare route configuration
3. Check service logs: `cd services/[service] && docker compose logs`
4. Verify service is on `web` network: `docker network inspect web`

### Federation not working (Matrix)
1. Test with [Federation Tester](https://federationtester.matrix.org/)
2. Verify both federation routes are configured in Cloudflare
3. Check "No TLS Verify" is enabled for federation routes
4. Check nginx logs: `docker compose -f services/matrix/docker-compose.yaml logs nginx`

## Security Notes

- Never commit `.env` files - the tunnel token is sensitive
- Each service should use strong, unique passwords
- Keep services updated regularly
- Monitor logs for suspicious activity
- Consider using Docker secrets for production deployments

## Split-Horizon DNS Fix

**Problem**: HTTPS requests were slow (~60s timeout) when using local DNS overrides because clients queried IPv6 (AAAA) records, got Cloudflare's IPv6 addresses, timed out, then fell back to IPv4.

**Solution**: In OpenWrt `/etc/dnsmasq.conf`, add:
```
address=/subdomain.domain.com/192.168.1.123
local=/subdomain.domain.com/
/etc/init.d/dnsmasq restart
```

This blocks upstream DNS forwarding for these domains, preventing IPv6 lookups from reaching Cloudflare.
Also add a block for the service in nginx reverse proxy which intercepts call to cloudflare and re-routes to local docker container.

## Let's Encrypt Certificates Setup

### 1. Create Cloudflare API Token
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. **Create Token** → Use template **"Edit zone DNS"**
3. Zone: `yourdomain.com`
4. **Create** and copy token

### 2. Configure Certbot
```bash
cd ~/self-hosting
mkdir -p certbot/{config,work,logs,ssl}

cat > certbot/cloudflare.ini << 'EOF'
dns_cloudflare_api_token = YOUR_TOKEN_HERE
EOF

chmod 600 certbot/cloudflare.ini
```

### 3. Start Certbot
```bash
docker compose up -d certbot
docker logs -f certbot  # Wait for "Successfully received certificate"
docker compose restart proxy
```
**Done!** Certificates auto-renew every 90 days.

## Monitor Versions with WUD and Gotify

1. Create Gotify App Token
   - Open browser: `https://gotify.yourdomain.com`
   - Login: `admin` / `admin`
   - **Apps** → **Create App** (e.g., "Docker Updates")
   - Copy token → Add to `.env`: `GOTIFY_TOKEN=<token>`
   - Restart WUD: `docker compose restart wud`

2. Test notification
   ```bash
   curl -X POST "https://gotify.yourdomain.com/message?token=YOUR_APP_TOKEN" \
     -d "title=Test&message=It works!&priority=3"
   ```

3. Add WUD Monitoring to Service Overrides

Add WUD labels to your override files to monitor specific containers:

**Example: `overrides/matrix.override.yaml`**
```yaml
services:
  synapse:
    labels:
      - "wud.watch=true"
      - "wud.tag.include=^v1\\.2\\.\\d+$$"  # v1.2.x only
    networks:
      - net
      - web
```

Notifications now appear on your phone and browser clients connected to Gotify.
