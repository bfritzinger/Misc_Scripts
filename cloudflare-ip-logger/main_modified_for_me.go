package main

import (
	"crypto/tls"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

type ConnectionLog struct {
	ID           int64     `json:"id"`
	Timestamp    time.Time `json:"-"`
	TimestampStr string    `json:"timestamp"`
	ClientIP     string    `json:"client_ip"`
	Country      string    `json:"country"`
	Method       string    `json:"method"`
	Path         string    `json:"path"`
	Host         string    `json:"host"`
	UserAgent    string    `json:"user_agent"`
	Referer      string    `json:"referer"`
}

type IPStats struct {
	ClientIP   string `json:"client_ip"`
	Country    string `json:"country"`
	HitCount   int    `json:"hit_count"`
	FirstSeen  string `json:"first_seen"`
	LastSeen   string `json:"last_seen"`
}

type ProxyConfig struct {
	Host    string `json:"host"`
	Backend string `json:"backend"`
	NoTLS   bool   `json:"no_tls_verify,omitempty"`
}

type App struct {
	db          *sql.DB
	logFile     *os.File
	logMutex    sync.Mutex
	proxies     map[string]*httputil.ReverseProxy
	backends    map[string]string
	backendURLs map[string]*url.URL
	noTLSHosts  map[string]bool
}

func main() {
	dataDir := getEnv("DATA_DIR", "/data")
	port := getEnv("PORT", "8080")
	configFile := getEnv("PROXY_CONFIG", dataDir+"/proxy-config.json")

	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatalf("Failed to create data directory: %v", err)
	}

	app := &App{
		proxies:     make(map[string]*httputil.ReverseProxy),
		backends:    make(map[string]string),
		backendURLs: make(map[string]*url.URL),
		noTLSHosts:  make(map[string]bool),
	}

	// Initialize database
	dbPath := dataDir + "/connections.db"
	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL")
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	app.db = db
	defer db.Close()

	if err := app.initDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Initialize log file
	logPath := dataDir + "/connections.log"
	logFile, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	app.logFile = logFile
	defer logFile.Close()

	// Load proxy config
	if err := app.loadProxyConfig(configFile); err != nil {
		log.Printf("Warning: Could not load proxy config from %s: %v", configFile, err)
		log.Println("Running in dashboard-only mode. Create proxy-config.json to enable reverse proxy.")
	}

	// API routes (these take priority) - using /_proxy/ to avoid conflicts with backend apps
	http.HandleFunc("/_proxy/connections", app.handleConnections)
	http.HandleFunc("/_proxy/stats", app.handleStats)
	http.HandleFunc("/_proxy/stats/ip/", app.handleIPStats)
	http.HandleFunc("/_proxy/health", app.handleHealth)
	http.HandleFunc("/_proxy/config", app.handleConfig)

	// Catch-all handler for dashboard and proxy
	http.HandleFunc("/", app.handleRequest)

	log.Printf("CF IP Logger starting on :%s", port)
	log.Printf("Database: %s", dbPath)
	log.Printf("Log file: %s", logPath)
	log.Printf("Proxy backends configured: %d", len(app.proxies))
	for host, backend := range app.backends {
		log.Printf("  %s -> %s", host, backend)
	}
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func (app *App) loadProxyConfig(configFile string) error {
	data, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}

	var configs []ProxyConfig
	if err := json.Unmarshal(data, &configs); err != nil {
		return err
	}

	for _, cfg := range configs {
		backendURL, err := url.Parse(cfg.Backend)
		if err != nil {
			log.Printf("Invalid backend URL for %s: %v", cfg.Host, err)
			continue
		}

		proxy := httputil.NewSingleHostReverseProxy(backendURL)

		// Customize the director to preserve the original Host header
		originalDirector := proxy.Director
		proxy.Director = func(req *http.Request) {
			originalHost := req.Host // Save original host (e.g., grafana.jbik.net)
			originalDirector(req)
			req.Host = originalHost // Restore it after director changes it
		}

		// Handle TLS verification
		if cfg.NoTLS {
			proxy.Transport = &http.Transport{
				TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
			}
		}

		hostKey := strings.ToLower(cfg.Host)
		app.proxies[hostKey] = proxy
		app.backends[hostKey] = cfg.Backend
		app.backendURLs[hostKey] = backendURL
		app.noTLSHosts[hostKey] = cfg.NoTLS
		log.Printf("Configured proxy: %s -> %s (noTLS: %v)", cfg.Host, cfg.Backend, cfg.NoTLS)
	}

	return nil
}

func (app *App) initDB() error {
	schema := `
	CREATE TABLE IF NOT EXISTS connections (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
		client_ip TEXT NOT NULL,
		country TEXT,
		method TEXT,
		path TEXT,
		host TEXT,
		user_agent TEXT,
		referer TEXT
	);
	CREATE INDEX IF NOT EXISTS idx_timestamp ON connections(timestamp);
	CREATE INDEX IF NOT EXISTS idx_client_ip ON connections(client_ip);
	CREATE INDEX IF NOT EXISTS idx_country ON connections(country);
	CREATE INDEX IF NOT EXISTS idx_host ON connections(host);
	`
	_, err := app.db.Exec(schema)
	return err
}

func (app *App) extractClientInfo(r *http.Request) ConnectionLog {
	clientIP := r.Header.Get("CF-Connecting-IP")
	if clientIP == "" {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			clientIP = strings.TrimSpace(strings.Split(xff, ",")[0])
		} else {
			clientIP = strings.Split(r.RemoteAddr, ":")[0]
		}
	}

	country := r.Header.Get("CF-IPCountry")
	if country == "" {
		country = "XX"
	}

	return ConnectionLog{
		Timestamp: time.Now(),
		ClientIP:  clientIP,
		Country:   country,
		Method:    r.Method,
		Path:      r.URL.Path,
		Host:      r.Host,
		UserAgent: r.Header.Get("User-Agent"),
		Referer:   r.Header.Get("Referer"),
	}
}

func (app *App) logConnection(conn ConnectionLog) error {
	// Log to database - store timestamp as formatted string
	_, err := app.db.Exec(`
		INSERT INTO connections (timestamp, client_ip, country, method, path, host, user_agent, referer)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		conn.Timestamp.Format("2006-01-02 15:04:05"), conn.ClientIP, conn.Country, conn.Method, conn.Path, conn.Host, conn.UserAgent, conn.Referer)
	if err != nil {
		return err
	}

	// Log to file
	app.logMutex.Lock()
	defer app.logMutex.Unlock()

	logLine := fmt.Sprintf("%s | %s | %s | %s %s | %s | %s\n",
		conn.Timestamp.Format("2006-01-02 15:04:05"),
		conn.ClientIP,
		conn.Country,
		conn.Method,
		conn.Path,
		conn.Host,
		conn.UserAgent)

	_, err = app.logFile.WriteString(logLine)
	return err
}

// Main request handler - routes to proxy or dashboard
func (app *App) handleRequest(w http.ResponseWriter, r *http.Request) {
	host := strings.ToLower(strings.Split(r.Host, ":")[0])

	// Log the connection
	conn := app.extractClientInfo(r)
	if err := app.logConnection(conn); err != nil {
		log.Printf("Error logging connection: %v", err)
	}
	log.Printf("%s (%s) -> %s %s %s", conn.ClientIP, conn.Country, conn.Host, conn.Method, conn.Path)

	// Check if we have a proxy for this host
	if _, ok := app.proxies[host]; ok {
		// Check if this is a WebSocket upgrade request
		if isWebSocketRequest(r) {
			app.handleWebSocket(w, r, host)
			return
		}
		app.proxies[host].ServeHTTP(w, r)
		return
	}

	// No proxy configured - show dashboard or IP info
	if r.URL.Path == "/" || r.URL.Path == "/dashboard" {
		app.handleDashboard(w, r)
		return
	}

	// Default: show visitor info
	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintf(w, "Your IP: %s\nCountry: %s\nHost: %s\nPath: %s\n", conn.ClientIP, conn.Country, conn.Host, conn.Path)
}

func isWebSocketRequest(r *http.Request) bool {
	return strings.ToLower(r.Header.Get("Upgrade")) == "websocket"
}

func (app *App) handleWebSocket(w http.ResponseWriter, r *http.Request, host string) {
	backendURL := app.backendURLs[host]
	if backendURL == nil {
		http.Error(w, "Backend not found", http.StatusBadGateway)
		return
	}

	// Determine backend address
	backendHost := backendURL.Host
	scheme := backendURL.Scheme

	// Dial the backend
	var backendConn net.Conn
	var err error

	if scheme == "https" {
		tlsConfig := &tls.Config{
			InsecureSkipVerify: app.noTLSHosts[host],
		}
		backendConn, err = tls.Dial("tcp", backendHost, tlsConfig)
	} else {
		backendConn, err = net.Dial("tcp", backendHost)
	}

	if err != nil {
		log.Printf("WebSocket backend dial error: %v", err)
		http.Error(w, "Backend connection failed", http.StatusBadGateway)
		return
	}
	defer backendConn.Close()

	// Hijack the client connection
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		log.Printf("Hijack error: %v", err)
		http.Error(w, "Hijack failed", http.StatusInternalServerError)
		return
	}
	defer clientConn.Close()

	// Forward the original request to the backend
	// Keep original Host header, just change the URL
	r.URL.Host = backendHost
	r.URL.Scheme = scheme
	r.RequestURI = ""
	r.Write(backendConn)

	// Bidirectional copy
	done := make(chan struct{})

	go func() {
		io.Copy(backendConn, clientConn)
		done <- struct{}{}
	}()

	go func() {
		io.Copy(clientConn, backendConn)
		done <- struct{}{}
	}()

	<-done
}

// GET /_proxy/connections?limit=100&offset=0&ip=x.x.x.x&country=US&since=2024-01-01&host=example.com
func (app *App) handleConnections(w http.ResponseWriter, r *http.Request) {
	// Log this request too
	conn := app.extractClientInfo(r)
	app.logConnection(conn)

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	query := r.URL.Query()
	limit, _ := strconv.Atoi(query.Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	offset, _ := strconv.Atoi(query.Get("offset"))

	filterIP := query.Get("ip")
	filterCountry := query.Get("country")
	filterHost := query.Get("host")
	since := query.Get("since")

	sqlQuery := `SELECT id, timestamp, client_ip, country, method, path, host, user_agent, referer 
		FROM connections WHERE 1=1`
	args := []interface{}{}

	if filterIP != "" {
		sqlQuery += " AND client_ip = ?"
		args = append(args, filterIP)
	}
	if filterCountry != "" {
		sqlQuery += " AND country = ?"
		args = append(args, filterCountry)
	}
	if filterHost != "" {
		sqlQuery += " AND host LIKE ?"
		args = append(args, "%"+filterHost+"%")
	}
	if since != "" {
		sqlQuery += " AND timestamp >= ?"
		args = append(args, since)
	}

	sqlQuery += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
	args = append(args, limit, offset)

	rows, err := app.db.Query(sqlQuery, args...)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var connections []ConnectionLog
	for rows.Next() {
		var c ConnectionLog
		err := rows.Scan(&c.ID, &c.TimestampStr, &c.ClientIP, &c.Country, &c.Method, &c.Path, &c.Host, &c.UserAgent, &c.Referer)
		if err != nil {
			continue
		}
		connections = append(connections, c)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(connections)
}

// GET /_proxy/stats?since=2024-01-01
func (app *App) handleStats(w http.ResponseWriter, r *http.Request) {
	// Log this request too
	conn := app.extractClientInfo(r)
	app.logConnection(conn)

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	since := r.URL.Query().Get("since")

	sqlQuery := `SELECT client_ip, country, COUNT(*) as hit_count, 
		MIN(timestamp) as first_seen, MAX(timestamp) as last_seen 
		FROM connections`
	args := []interface{}{}

	if since != "" {
		sqlQuery += " WHERE timestamp >= ?"
		args = append(args, since)
	}

	sqlQuery += " GROUP BY client_ip ORDER BY hit_count DESC LIMIT 100"

	rows, err := app.db.Query(sqlQuery, args...)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var stats []IPStats
	for rows.Next() {
		var s IPStats
		err := rows.Scan(&s.ClientIP, &s.Country, &s.HitCount, &s.FirstSeen, &s.LastSeen)
		if err != nil {
			continue
		}
		stats = append(stats, s)
	}

	// Get totals
	var totalConnections int
	var uniqueIPs int
	app.db.QueryRow("SELECT COUNT(*), COUNT(DISTINCT client_ip) FROM connections").Scan(&totalConnections, &uniqueIPs)

	// Get host stats
	hostRows, _ := app.db.Query("SELECT host, COUNT(*) as hits FROM connections GROUP BY host ORDER BY hits DESC LIMIT 20")
	defer hostRows.Close()

	hostStats := make(map[string]int)
	for hostRows.Next() {
		var host string
		var hits int
		hostRows.Scan(&host, &hits)
		hostStats[host] = hits
	}

	response := map[string]interface{}{
		"total_connections": totalConnections,
		"unique_ips":        uniqueIPs,
		"top_ips":           stats,
		"top_hosts":         hostStats,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GET /_proxy/stats/ip/{ip}
func (app *App) handleIPStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ip := strings.TrimPrefix(r.URL.Path, "/_proxy/stats/ip/")
	if ip == "" {
		http.Error(w, "IP required", http.StatusBadRequest)
		return
	}

	var stats IPStats
	err := app.db.QueryRow(`
		SELECT client_ip, country, COUNT(*) as hit_count, 
		MIN(timestamp) as first_seen, MAX(timestamp) as last_seen 
		FROM connections WHERE client_ip = ? GROUP BY client_ip`, ip).
		Scan(&stats.ClientIP, &stats.Country, &stats.HitCount, &stats.FirstSeen, &stats.LastSeen)

	if err == sql.ErrNoRows {
		http.Error(w, "IP not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Get recent paths
	rows, _ := app.db.Query(`SELECT DISTINCT path, host FROM connections WHERE client_ip = ? ORDER BY timestamp DESC LIMIT 20`, ip)
	defer rows.Close()

	type PathHost struct {
		Path string `json:"path"`
		Host string `json:"host"`
	}
	var paths []PathHost
	for rows.Next() {
		var ph PathHost
		rows.Scan(&ph.Path, &ph.Host)
		paths = append(paths, ph)
	}

	response := map[string]interface{}{
		"stats":        stats,
		"recent_paths": paths,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GET /_proxy/health
func (app *App) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// GET /_proxy/config - show current proxy configuration
func (app *App) handleConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(app.backends)
}

// GET / - Dashboard
func (app *App) handleDashboard(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html>
<head>
    <title>IP Logger</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; 
            background: #111827; 
            color: #e5e7eb; 
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 24px; }
        
        /* Header */
        .header { 
            display: flex; 
            align-items: center; 
            justify-content: space-between;
            margin-bottom: 32px; 
            padding-bottom: 24px;
            border-bottom: 1px solid #374151;
        }
        .header-left { display: flex; align-items: center; gap: 16px; }
        .logo { 
            height: 80px; 
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
        }
        h1 { 
            font-size: 1.875rem; 
            font-weight: 700; 
            color: #f9fafb; 
        }
        .subtitle { color: #9ca3af; font-size: 0.875rem; margin-top: 4px; }
        
        /* Refresh button */
        .refresh-btn { 
            background: #10b981; 
            color: #fff; 
            border: none; 
            padding: 10px 20px; 
            border-radius: 8px; 
            cursor: pointer; 
            font-weight: 500;
            font-size: 0.875rem;
            transition: background 0.2s;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .refresh-btn:hover { background: #059669; }
        
        /* Stats grid */
        .stats-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 16px; 
            margin-bottom: 32px; 
        }
        .stat-card { 
            background: #1f2937; 
            padding: 24px; 
            border-radius: 12px; 
            border: 1px solid #374151;
        }
        .stat-label { 
            color: #9ca3af; 
            font-size: 0.875rem; 
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 8px;
        }
        .stat-value { 
            font-size: 2.25rem; 
            font-weight: 700; 
            color: #10b981; 
        }
        
        /* Sections */
        .section { margin-bottom: 32px; }
        h2 { 
            color: #f9fafb; 
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        h2::before {
            content: '';
            width: 4px;
            height: 20px;
            background: #10b981;
            border-radius: 2px;
        }
        
        /* Tables */
        .table-container {
            background: #1f2937;
            border-radius: 12px;
            border: 1px solid #374151;
            overflow: hidden;
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
        }
        th, td { 
            padding: 12px 16px; 
            text-align: left; 
        }
        th { 
            background: #374151; 
            color: #d1d5db; 
            font-weight: 600;
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        td {
            border-bottom: 1px solid #374151;
            font-size: 0.875rem;
        }
        tr:last-child td { border-bottom: none; }
        tr:hover td { background: #263244; }
        
        /* Tags */
        .host-tag { 
            background: #10b981; 
            color: #fff;
            padding: 4px 10px; 
            border-radius: 6px; 
            font-size: 0.75rem;
            font-weight: 500;
        }
        .country-tag {
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }
        .method-tag {
            background: #3b82f6;
            color: #fff;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 600;
        }
        .method-tag.post { background: #f59e0b; }
        .method-tag.delete { background: #ef4444; }
        .method-tag.put { background: #8b5cf6; }
        
        /* IP styling */
        .ip-address {
            font-family: 'Monaco', 'Menlo', monospace;
            color: #60a5fa;
        }
        .path {
            font-family: 'Monaco', 'Menlo', monospace;
            color: #9ca3af;
            font-size: 0.8rem;
        }
        .timestamp {
            color: #6b7280;
            font-size: 0.8rem;
        }
        
        /* Status indicator */
        .status-dot {
            width: 8px;
            height: 8px;
            background: #10b981;
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-left">
                <img src="data:image/jpeg;base64,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" alt="IP Logger" class="logo">
                <div>
                    <h1>IP Logger</h1>
                    <div class="subtitle"><span class="status-dot"></span>Monitoring network traffic</div>
                </div>
            </div>
            <button class="refresh-btn" onclick="loadData()">
                <svg width="16" height="16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                Refresh
            </button>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-label">Total Connections</div>
                <div class="stat-value" id="total-connections">-</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Unique IPs</div>
                <div class="stat-value" id="unique-ips">-</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Countries</div>
                <div class="stat-value" id="countries">-</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Services</div>
                <div class="stat-value" id="hosts">-</div>
            </div>
        </div>

        <div class="section">
            <h2>Top IPs</h2>
            <div class="table-container">
                <table>
                    <thead><tr><th>IP Address</th><th>Country</th><th>Hits</th><th>First Seen</th><th>Last Seen</th></tr></thead>
                    <tbody id="top-ips"></tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <h2>Top Services</h2>
            <div class="table-container">
                <table>
                    <thead><tr><th>Host</th><th>Hits</th></tr></thead>
                    <tbody id="top-hosts"></tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <h2>Recent Connections</h2>
            <div class="table-container">
                <table>
                    <thead><tr><th>Time</th><th>IP</th><th>Country</th><th>Host</th><th>Method</th><th>Path</th></tr></thead>
                    <tbody id="recent-connections"></tbody>
                </table>
            </div>
        </div>
    </div>

    <script>
        function countryFlag(code) {
            if (!code || code === 'XX') return '🌍';
            return code.toUpperCase().replace(/./g, c => String.fromCodePoint(127397 + c.charCodeAt()));
        }
        
        function methodClass(method) {
            const m = method.toLowerCase();
            if (m === 'post') return 'method-tag post';
            if (m === 'delete') return 'method-tag delete';
            if (m === 'put' || m === 'patch') return 'method-tag put';
            return 'method-tag';
        }

        async function loadData() {
            try {
                const [statsRes, connectionsRes] = await Promise.all([
                    fetch('/api/stats'),
                    fetch('/api/connections?limit=50')
                ]);
                
                const stats = await statsRes.json();
                const connections = await connectionsRes.json();

                document.getElementById('total-connections').textContent = stats.total_connections.toLocaleString();
                document.getElementById('unique-ips').textContent = stats.unique_ips.toLocaleString();
                
                const countries = new Set(stats.top_ips?.map(s => s.country) || []);
                document.getElementById('countries').textContent = countries.size;

                const hostCount = Object.keys(stats.top_hosts || {}).length;
                document.getElementById('hosts').textContent = hostCount;

                const topIpsHtml = (stats.top_ips || []).slice(0, 20).map(ip => 
                    '<tr><td><span class="ip-address">' + ip.client_ip + '</span></td>' +
                    '<td><span class="country-tag">' + countryFlag(ip.country) + ' ' + ip.country + '</span></td>' +
                    '<td>' + ip.hit_count + '</td>' +
                    '<td><span class="timestamp">' + ip.first_seen + '</span></td>' +
                    '<td><span class="timestamp">' + ip.last_seen + '</span></td></tr>'
                ).join('');
                document.getElementById('top-ips').innerHTML = topIpsHtml || '<tr><td colspan="5">No data</td></tr>';

                const topHostsHtml = Object.entries(stats.top_hosts || {}).map(([host, hits]) =>
                    '<tr><td><span class="host-tag">' + host + '</span></td><td>' + hits + '</td></tr>'
                ).join('');
                document.getElementById('top-hosts').innerHTML = topHostsHtml || '<tr><td colspan="2">No data</td></tr>';

                const connectionsHtml = (connections || []).map(c => 
                    '<tr><td><span class="timestamp">' + c.timestamp + '</span></td>' +
                    '<td><span class="ip-address">' + c.client_ip + '</span></td>' +
                    '<td><span class="country-tag">' + countryFlag(c.country) + ' ' + c.country + '</span></td>' +
                    '<td><span class="host-tag">' + (c.host || '-') + '</span></td>' +
                    '<td><span class="' + methodClass(c.method) + '">' + c.method + '</span></td>' +
                    '<td><span class="path">' + c.path + '</span></td></tr>'
                ).join('');
                document.getElementById('recent-connections').innerHTML = connectionsHtml || '<tr><td colspan="6">No data</td></tr>';
            } catch (err) {
                console.error('Error loading data:', err);
            }
        }

        loadData();
        setInterval(loadData, 30000);
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html")
	fmt.Fprint(w, html)
}