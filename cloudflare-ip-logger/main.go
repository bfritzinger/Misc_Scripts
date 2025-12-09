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

	// API routes (these take priority)
	http.HandleFunc("/api/connections", app.handleConnections)
	http.HandleFunc("/api/stats", app.handleStats)
	http.HandleFunc("/api/stats/ip/", app.handleIPStats)
	http.HandleFunc("/api/health", app.handleHealth)
	http.HandleFunc("/api/config", app.handleConfig)

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

// GET /api/connections?limit=100&offset=0&ip=x.x.x.x&country=US&since=2024-01-01&host=example.com
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

// GET /api/stats?since=2024-01-01
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

// GET /api/stats/ip/{ip}
func (app *App) handleIPStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ip := strings.TrimPrefix(r.URL.Path, "/api/stats/ip/")
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

// GET /api/health
func (app *App) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// GET /api/config - show current proxy configuration
func (app *App) handleConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(app.backends)
}

// GET / - Dashboard
func (app *App) handleDashboard(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html>
<head>
    <title>CF IP Logger Dashboard</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: #1a1a2e; color: #eee; }
        h1 { color: #00d4ff; margin-bottom: 20px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: #16213e; padding: 20px; border-radius: 10px; text-align: center; }
        .stat-value { font-size: 2.5em; font-weight: bold; color: #00d4ff; }
        .stat-label { color: #888; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; background: #16213e; border-radius: 10px; overflow: hidden; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #0f3460; }
        th { background: #0f3460; color: #00d4ff; }
        tr:hover { background: #1a1a4e; }
        .refresh-btn { background: #00d4ff; color: #1a1a2e; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin-bottom: 20px; }
        .refresh-btn:hover { background: #00a8cc; }
        .country-flag { margin-right: 8px; }
        .section { margin-bottom: 30px; }
        h2 { color: #00d4ff; border-bottom: 2px solid #0f3460; padding-bottom: 10px; }
        .host-tag { background: #0f3460; padding: 2px 8px; border-radius: 4px; font-size: 0.85em; }
    </style>
</head>
<body>
    <h1>🌐 CF IP Logger Dashboard</h1>
    <button class="refresh-btn" onclick="loadData()">↻ Refresh</button>
    
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value" id="total-connections">-</div>
            <div class="stat-label">Total Connections</div>
        </div>
        <div class="stat-card">
            <div class="stat-value" id="unique-ips">-</div>
            <div class="stat-label">Unique IPs</div>
        </div>
        <div class="stat-card">
            <div class="stat-value" id="countries">-</div>
            <div class="stat-label">Countries</div>
        </div>
        <div class="stat-card">
            <div class="stat-value" id="hosts">-</div>
            <div class="stat-label">Services</div>
        </div>
    </div>

    <div class="section">
        <h2>Top IPs</h2>
        <table>
            <thead><tr><th>IP Address</th><th>Country</th><th>Hits</th><th>First Seen</th><th>Last Seen</th></tr></thead>
            <tbody id="top-ips"></tbody>
        </table>
    </div>

    <div class="section">
        <h2>Top Services</h2>
        <table>
            <thead><tr><th>Host</th><th>Hits</th></tr></thead>
            <tbody id="top-hosts"></tbody>
        </table>
    </div>

    <div class="section">
        <h2>Recent Connections</h2>
        <table>
            <thead><tr><th>Time</th><th>IP</th><th>Country</th><th>Host</th><th>Method</th><th>Path</th></tr></thead>
            <tbody id="recent-connections"></tbody>
        </table>
    </div>

    <script>
        function countryFlag(code) {
            if (!code || code === 'XX') return '🌍';
            return code.toUpperCase().replace(/./g, c => String.fromCodePoint(127397 + c.charCodeAt()));
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
                    '<tr><td>' + ip.client_ip + '</td><td>' + countryFlag(ip.country) + ' ' + ip.country + 
                    '</td><td>' + ip.hit_count + '</td><td>' + ip.first_seen + '</td><td>' + ip.last_seen + '</td></tr>'
                ).join('');
                document.getElementById('top-ips').innerHTML = topIpsHtml || '<tr><td colspan="5">No data</td></tr>';

                const topHostsHtml = Object.entries(stats.top_hosts || {}).map(([host, hits]) =>
                    '<tr><td><span class="host-tag">' + host + '</span></td><td>' + hits + '</td></tr>'
                ).join('');
                document.getElementById('top-hosts').innerHTML = topHostsHtml || '<tr><td colspan="2">No data</td></tr>';

                const connectionsHtml = (connections || []).map(c => 
                    '<tr><td>' + c.timestamp + '</td><td>' + c.client_ip + 
                    '</td><td>' + countryFlag(c.country) + ' ' + c.country + '</td><td><span class="host-tag">' + (c.host || '-') + '</span>' +
                    '</td><td>' + c.method + '</td><td>' + c.path + '</td></tr>'
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
