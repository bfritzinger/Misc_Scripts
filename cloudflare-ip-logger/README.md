# CF IP Logger

A reverse proxy that logs visitor IPs from Cloudflare Tunnel traffic. All traffic flows through the logger, which captures the real visitor IP from Cloudflare headers, then forwards to your backend services.

## Features

- **Reverse Proxy**: Routes traffic to your backend services based on hostname
- **Captures Cloudflare headers**: `CF-Connecting-IP`, `CF-IPCountry`
- **SQLite database**: Persistent storage with efficient indexing
- **File logging**: Simple text log file for external tools
- **REST API**: Query connections and statistics
- **Web Dashboard**: Real-time stats
- **ARM64 compatible**: Works on Raspberry Pi and other ARM hosts

## How It Works

```
Internet → Cloudflare → cloudflared → cf-ip-logger → your services
                                         ↓
                                    logs visitor IP
```

All your services are proxied through cf-ip-logger, which:
1. Reads the `CF-Connecting-IP` header (real visitor IP)
2. Logs the connection to SQLite
3. Forwards the request to the actual backend

## Quick Start

1. **Copy the example config:**
   ```bash
   cp proxy-config.json.example data/cf-ip-logger/proxy-config.json
   ```

2. **Edit the config** with your services:
   ```json
   [
     {
       "host": "grafana.example.com",
       "backend": "http://10.0.0.1:3000"
     },
     {
       "host": "app.example.com",
       "backend": "https://10.0.0.2:443",
       "no_tls_verify": true
     }
   ]
   ```

3. **Start the logger:**
   ```bash
   docker compose up -d --build
   ```

4. **Update cloudflared** to point ALL services to the logger:
   ```yaml
   tunnel: <your-tunnel-id>
   ingress:
     - hostname: grafana.example.com
       service: http://10.0.0.155:8080
       originRequest:
         httpHostHeader: grafana.example.com
     - hostname: app.example.com
       service: http://10.0.0.155:8080
       originRequest:
         httpHostHeader: app.example.com
     - hostname: iplog.example.com
       service: http://10.0.0.155:8080
     - service: http_status:404
   ```

5. **Access the dashboard** at `https://iplog.example.com/` or any hostname not in your proxy config.

## Cloudflared Configuration

The key is `originRequest.httpHostHeader` — this tells cloudflared to preserve the original hostname in the Host header, which cf-ip-logger uses to route to the correct backend.

**Before (direct to services):**
```yaml
ingress:
  - hostname: grafana.example.com
    service: http://10.0.0.214:30300
```

**After (through logger):**
```yaml
ingress:
  - hostname: grafana.example.com
    service: http://10.0.0.155:8080
    originRequest:
      httpHostHeader: grafana.example.com
```

## Proxy Config Reference

`proxy-config.json` is an array of backend mappings:

| Field | Required | Description |
|-------|----------|-------------|
| `host` | Yes | Hostname to match (case-insensitive) |
| `backend` | Yes | Backend URL to proxy to |
| `no_tls_verify` | No | Skip TLS certificate verification |

## API Reference

### GET /api/connections

Retrieve connection logs with optional filtering.

**Parameters:**
- `limit` (int): Max results, default 100, max 1000
- `offset` (int): Pagination offset
- `ip` (string): Filter by IP address
- `country` (string): Filter by country code
- `host` (string): Filter by hostname
- `since` (string): Filter by date (YYYY-MM-DD)

### GET /api/stats

Get aggregated statistics including top IPs and top hosts.

### GET /api/stats/ip/{ip}

Get detailed stats for a specific IP.

### GET /api/config

Show current proxy configuration.

### GET /api/health

Health check endpoint.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATA_DIR` | `/data` | Directory for database and config |
| `PORT` | `8080` | HTTP server port |
| `TZ` | UTC | Timezone |

## Data Storage

Data is stored in `/data`:

- `connections.db` - SQLite database
- `connections.log` - Plain text log file  
- `proxy-config.json` - Backend routing config

## Querying SQLite Directly

```bash
sqlite3 ./data/cf-ip-logger/connections.db

# Recent connections
SELECT * FROM connections ORDER BY timestamp DESC LIMIT 10;

# Top IPs
SELECT client_ip, COUNT(*) as hits FROM connections GROUP BY client_ip ORDER BY hits DESC;

# Top hosts
SELECT host, COUNT(*) as hits FROM connections GROUP BY host ORDER BY hits DESC;

# Connections by country
SELECT country, COUNT(*) as hits FROM connections GROUP BY country ORDER BY hits DESC;
```
