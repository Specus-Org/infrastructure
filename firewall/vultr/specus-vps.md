# Vultr Cloud Firewall: Specus VPS

Single VPS running all services (PostgreSQL, Redis, Airflow, Dokploy, wg-easy).

## Architecture

```
Internet ──→ WireGuard UDP 51820 (Public)
           │
           ├──→ HTTPS 443 (Traefik) ──→ wg-easy UI (vpn.specus.id)
           │
           ↓ (after VPN connection)
           VPN Network 10.8.0.0/24
           ├── SSH 22
           ├── Dokploy 3000
           ├── wg-easy UI 51821
           ├── PostgreSQL 5432
           ├── Redis 6379
           └── Airflow 8080
```

## Inbound Rules

### Public Access (0.0.0.0/0)

| Protocol | Port  | Source    | Description                     |
|----------|-------|----------|---------------------------------|
| UDP      | 51820 | 0.0.0.0/0 | WireGuard VPN tunnel          |
| TCP      | 80    | 0.0.0.0/0 | HTTP (redirect to HTTPS)      |
| TCP      | 443   | 0.0.0.0/0 | HTTPS (Traefik reverse proxy) |

### VPN-Only Access (10.8.0.0/24)

| Protocol | Port  | Source       | Description              |
|----------|-------|--------------|--------------------------|
| TCP      | 22    | 10.8.0.0/24  | SSH                      |
| TCP      | 3000  | 10.8.0.0/24  | Dokploy UI               |
| TCP      | 51821 | 10.8.0.0/24  | wg-easy admin UI         |
| TCP      | 5432  | 10.8.0.0/24  | PostgreSQL               |
| TCP      | 6379  | 10.8.0.0/24  | Redis                    |
| TCP      | 8080  | 10.8.0.0/24  | Airflow API server       |
| ICMP     | -     | 10.8.0.0/24  | Ping                     |

## Outbound Rules

Allow all outbound traffic (default).

## Setup Instructions

1. Go to **Vultr Dashboard > Products > Firewall**
2. Create a new firewall group named `specus-vps`
3. Add the inbound rules from tables above
4. Attach the firewall group to the Specus VPS instance
5. **Verify the firewall is active** before running `setup-vps.sh` -- the cloud firewall must be in place first so services are never exposed on bare ports during provisioning

## Security Notes

- **Defense-in-depth**: This cloud firewall is the first layer. Services also bind to localhost or Docker networks.
- **SSH is VPN-only**: You must connect to WireGuard VPN before SSH access is available.
- **Database ports are VPN-only**: PostgreSQL and Redis are never exposed to the public internet.
- **wg-easy UI port 51821 is VPN-only**: Direct admin interface access requires VPN connection.
- **wg-easy HTTPS is public**: Optionally, a domain (e.g. vpn.specus.id) routes through Traefik on port 443 for HTTPS login. Access is protected by wg-easy's built-in username/password authentication. Use a strong password.
- **HTTP/HTTPS are public**: Traefik handles TLS termination and routes to internal services.
- **Dokploy deployments**: Because port 3000 is VPN-only, Dokploy cannot receive external webhooks (e.g., from GitHub). Configure Dokploy to use **polling-based** deployments, or trigger deploys manually / via SSH over the VPN.
