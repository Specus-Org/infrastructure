# Domain Migration: procurelens.org → specus.biz

Runbook for migrating all public services from `procurelens.org` to `specus.biz`.
Execute steps in order — each step depends on the previous one.

## Pre-requisites

- [ ] Code changes merged (config files already reference `specus.biz`)
- [ ] Access to: Cloudflare, Dokploy UI, SendGrid, VPS SSH

## Domain Mapping

| Service | Old Domain | New Domain | Port |
|---------|-----------|------------|------|
| Authentik (SSO) | `auth.procurelens.org` | `auth.specus.biz` | 9000 |
| Garage S3 API | `storage.procurelens.org` | `storage.specus.biz` | 3900 |
| Garage CDN | `cdn.procurelens.org` | `cdn.specus.biz` | 3902 |
| wg-easy VPN | `vpn.procurelens.org` | `vpn.specus.biz` | 51821 |

| Purpose | Old Address | New Address |
|---------|------------|-------------|
| Admin email | `admin@procurelens.org` | `admin@specus.biz` |
| Sender email | `noreply@procurelens.org` | `noreply@specus.biz` |

---

## Step 1: Cloudflare DNS

Create A records pointing to the VPS IP. Keep old `procurelens.org` records active during transition.

| Type | Name | Target | Proxy |
|------|------|--------|-------|
| A | `auth.specus.biz` | `<VPS-IP>` | Proxied |
| A | `storage.specus.biz` | `<VPS-IP>` | Proxied |
| A | `cdn.specus.biz` | `<VPS-IP>` | Proxied |
| A | `vpn.specus.biz` | `<VPS-IP>` | Proxied |

**Verify**: `dig +short auth.specus.biz` should resolve (may show Cloudflare IPs if proxied).

---

## Step 2: Dokploy — Add New Domains

Add new domains **before** removing old ones so there's no downtime.

### Garage service → Domains

1. Add `storage.specus.biz` → port `3900`, HTTPS enabled
2. Add `cdn.specus.biz` → port `3902`, HTTPS enabled
3. Wait for Let's Encrypt certs to issue (check Traefik logs in Dokploy)
4. Verify:
   - `curl -I https://storage.specus.biz` → should return 403 (S3 auth required)
   - `curl -I https://cdn.specus.biz` → should respond
5. Remove old `storage.procurelens.org` and `cdn.procurelens.org` domains

### Authentik service → Domains

1. Add `auth.specus.biz` → port `9000`, HTTPS enabled
2. Wait for Let's Encrypt cert
3. Verify: `https://auth.specus.biz` → login page loads
4. Remove old `auth.procurelens.org` domain

---

## Step 3: Garage — Redeploy and Update Bucket Alias

Redeploy the Garage service in Dokploy UI. The updated `garage.toml` (with `specus.biz` root domains) is already in the repo and will be picked up automatically.

After redeployment, update the bucket alias so the web gateway maps `cdn.specus.biz` to the `lexicon` bucket:

```bash
# Add new alias
docker exec -it <garage-container> garage bucket alias set --global cdn.specus.biz lexicon

# Remove old alias
docker exec -it <garage-container> garage bucket alias unset --global cdn.procurelens.org
```

**Verify**: `curl https://cdn.specus.biz/lexicon/` → should list or serve bucket contents.

---

## Step 4: Authentik — Update Environment Variables

In Dokploy UI → Authentik service → Environment, update these values:

```
AUTHENTIK_DOMAIN=auth.specus.biz
AUTHENTIK_S3_ENDPOINT=https://storage.specus.biz
AUTHENTIK_BOOTSTRAP_EMAIL=admin@specus.biz
AUTHENTIK_EMAIL_FROM=noreply@specus.biz
```

Redeploy Authentik service.

---

## Step 5: Authentik — Update Admin UI (Database Config)

Log into `https://auth.specus.biz` as admin. These settings are stored in the database and must be updated through the UI.

### 5a. Update Brand

1. Go to **System → Brands**
2. Edit the brand currently mapped to `auth.procurelens.org`
3. Change **Domain** field to `auth.specus.biz`
4. Save

### 5b. Update OAuth2/OIDC Providers

1. Go to **Applications → Providers**
2. For each OAuth2/OIDC provider:
   - Check **Redirect URIs** — update any containing `procurelens.org` to `specus.biz`
   - The issuer URL is auto-generated from the brand domain, but verify it shows `specus.biz`
3. Save each provider

### 5c. Update Applications

1. Go to **Applications → Applications**
2. For each application:
   - Check **Launch URL** — update any containing `procurelens.org` to `specus.biz`
3. Save each application

### 5d. Update Outposts (if any)

1. Go to **Applications → Outposts**
2. Check if `authentik_host` references `procurelens.org`
3. Update to `https://auth.specus.biz`
4. Save

**Verify**: Test a full OAuth login flow through one of the configured applications.

---

## Step 6: SendGrid — Verify New Sender Domain

The email sender changes from `noreply@procurelens.org` to `noreply@specus.biz`. SendGrid must verify the new domain before emails can be sent.

1. In SendGrid dashboard → **Settings → Sender Authentication**
2. Add `specus.biz` as an authenticated domain
3. Add the required DNS records in Cloudflare:
   - 3x CNAME records for DKIM
   - TXT record for SPF (if not using domain authentication)
4. Wait for SendGrid to verify (usually a few minutes)
5. Optionally add `noreply@specus.biz` as a verified single sender

**Verify**: Send a test email from Authentik (e.g., password reset) and confirm delivery.

---

## Step 7: wg-easy — Update Traefik Config (if applicable)

If wg-easy HTTPS access is configured with a `procurelens.org` domain, update the Traefik dynamic config on the VPS:

```bash
# Edit: /etc/dokploy/traefik/dynamic/wg-easy.yml
# Find the Host rule and change to vpn.specus.biz
# Example: rule: Host(`vpn.specus.biz`)
```

Traefik auto-reloads file provider changes — no restart needed.

> If wg-easy uses `vpn.specus.id`, skip this step.

---

## Step 8: Downstream Applications

Update environment variables in any application that connects to Garage or Authentik:

```
S3_ENDPOINT=https://storage.specus.biz
S3_PUBLIC_BASE_URL=https://cdn.specus.biz/lexicon
```

Public URLs in CMS content change pattern:
```
https://cdn.procurelens.org/lexicon/uploads/... → https://cdn.specus.biz/lexicon/uploads/...
```

---

## Step 9: Verification Checklist

- [ ] `https://auth.specus.biz` → Authentik login page loads with valid TLS
- [ ] `https://storage.specus.biz` → S3 API responds (403 without credentials = working)
- [ ] `https://cdn.specus.biz` → Web gateway responds
- [ ] `https://vpn.specus.biz` → wg-easy UI loads (if configured)
- [ ] Authentik media upload works (uploads to Garage via S3)
- [ ] Password reset email arrives from `noreply@specus.biz`
- [ ] OAuth/OIDC login flow completes with new redirect URIs
- [ ] Existing S3 objects accessible via `cdn.specus.biz`
- [ ] No mixed-content or redirect loops (Cloudflare SSL mode = Full)

---

## Step 10: Cleanup

After a few days of confirmed stability:

- [ ] Remove `*.procurelens.org` A records from Cloudflare
- [ ] Remove any remaining old domain entries from Dokploy
- [ ] Revoke old SendGrid sender authentication for `procurelens.org` (optional)
- [ ] Delete this migration document (or move to an archive)
