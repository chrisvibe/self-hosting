# Self-Hosting Infrastructure
Personal self-hosted services infrastructure with optional Cloudflare Tunnel and Tailscale integration.

# Install
```bash
git clone --recursive git@github.com:chrisvibe/self-hosting.git
```

## Architecture

```
Internet → [Optional: Cloudflare Tunnel] → Docker Network (web) → Services
                                                                   ├─ Service 1
                                                                   ├─ Service 2
                                                                   └─ ...
```

**Note**: If not using Cloudflare Tunnel, handle SSL termination yourself (Let's Encrypt, nginx reverse proxy, etc.)

## Project Structure

```
self-hosting/
├── docker-compose.yaml          # [Optional] Cloudflare tunnel
├── env_template / .env          # [Optional] Tunnel token
├── overrides/                   # Service network overrides
│   └── service.override.yaml
├── scripts/                     # Setup scripts
│   └── setup-service.sh
└── services/                    # Cloned service repos (gitignored)
    └── service-name/            # Created by setup script
```

## Initial Setup

### 1. Create Shared Network

```bash
docker network create web
```

### 2. (Optional) Configure Cloudflare Tunnel

If exposing services to the internet via Cloudflare:

1. Log into Cloudflare Dashboard
2. Go to **Zero Trust** → **Networks** → **Tunnels**
3. Create a new tunnel (choose Docker connector)
4. Copy the tunnel token
5. Configure environment:
   ```bash
   cp env_template .env
   # Edit .env and add: CLOUDFLARE_TUNNEL_TOKEN='your_token_here'
   ```
6. Start tunnel:
   ```bash
   docker compose up -d
   ```

## Adding Services

General pattern for each service:

1. Create override file in `overrides/service.override.yaml`
2. Create setup script in `scripts/setup-service.sh`
3. Run setup script
4. Configure service in `services/service-name/`
5. Start service: `cd services/service-name && docker compose up -d`
6. (Optional) Add Cloudflare route if exposing publicly

### Example: Matrix Server

See Matrix as a reference implementation. The setup script:
- Clones the service repository
- Symlinks the network override
- Creates initial `.env` file

Then configure Cloudflare routes (if using tunnel) to point to the service's exposed container.

## Network Architecture

- **web network**: Shared bridge network that all services and the tunnel join
- Each service can also have internal networks for inter-service communication
- Tunnel → web network → service nginx/proxy → internal service network

## Updating Services

```bash
cd services/service-name
git pull
docker compose pull
docker compose up -d
```

## Backup

Each service should handle its own backups. Check service-specific documentation for backup procedures.

## Troubleshooting

### Service not accessible from internet
1. If using Cloudflare: Check tunnel is running (`docker compose ps` in self-hosting root)
2. If using Cloudflare: Verify route configuration in Cloudflare Dashboard
3. Check service logs: `cd services/[service] && docker compose logs`
4. Verify service is on `web` network: `docker network inspect web`
5. If not using Cloudflare: Verify your SSL termination and port forwarding

## Security Notes

- Never commit `.env` files - the tunnel token is sensitive
- Each service should use strong, unique passwords
- Keep services updated regularly
- Monitor logs for suspicious activity
- Consider using Docker secrets for production deployments

## Split-Horizon DNS (Optional - for tunnel users with local access)

**Purpose**: Optimize local network access when using tunneling solutions (Cloudflare, Tailscale, etc.) by routing local clients directly to services instead of through external tunnels.

**Problem**: Clients queried IPv6 (AAAA) records, got tunnel provider's addresses, timed out (~60s), then fell back to IPv4.

**Solution**: In OpenWrt `/etc/dnsmasq.conf`, add:
```
address=/subdomain.domain.com/192.168.1.123
local=/subdomain.domain.com/
/etc/init.d/dnsmasq restart
```

This blocks upstream DNS forwarding for these domains, preventing lookups from reaching tunnel providers. Also configure your local nginx reverse proxy to intercept these requests and route to local Docker containers.

**If using Tailscale**: Tailscale's MagicDNS overrides local DNS. Force clients to use your router as primary DNS:
```bash
uci add_list dhcp.lan.dhcp_option="6,192.168.1.1"
uci commit dhcp
/etc/init.d/dnsmasq restart
```

This sets DHCP option 6 (DNS server) to your router's IP, ensuring split-horizon DNS takes precedence.

## Let's Encrypt Certificates (Optional - for Cloudflare DNS challenge)

If using Cloudflare for DNS but want to manage your own certificates:

### 1. Create Cloudflare API Token
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. **Create Token** → Use template **"Edit zone DNS"**
3. Zone: `yourdomain.com`
4. Copy token

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
Certificates auto-renew every 90 days.

## Monitor Versions with WUD and Gotify (Optional)

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

**Example: `overrides/service.override.yaml`**
```yaml
services:
  container-name:
    labels:
      - "wud.watch=true"
      - "wud.tag.include=^v1\\.2\\.\\d+$$"  # Regex for version filtering
    networks:
      - default
      - web
```

Notifications appear on your phone and browser clients connected to Gotify.

## Headscale + Tailscale (Optional - for redundant access)

Deploy Headscale + Tailscale on a separate server for multiple entry points if Cloudflare tunnel goes down.
