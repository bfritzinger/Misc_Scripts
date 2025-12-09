package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"flag"
	"log"
	"os"
	"regexp"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// CloudflaredLogEntry represents a JSON log line from cloudflared
type CloudflaredLogEntry struct {
	Time       string `json:"time"`
	Level      string `json:"level"`
	Message    string `json:"message"`
	Msg        string `json:"msg"`
	Origin     string `json:"originURL"`
	ClientIP   string `json:"clientIP"`
	CFRay      string `json:"cfRay"`
	IP         string `json:"ip"`
	Location   string `json:"location"`
	FlowID     string `json:"flowId"`
	Dest       string `json:"dest"`
	Rule       int    `json:"ingressRule"`
	Hostname   string `json:"hostname"`
	Error      string `json:"error"`
	ConnIndex  int    `json:"connIndex"`
	TraceID    string `json:"traceId"`
	Status     int    `json:"status"`
	Duration   int64  `json:"duration"`
	Method     string `json:"method"`
	Path       string `json:"path"`
	RuleName   string `json:"ruleName"`
}

// Regex patterns for non-JSON logs
var (
	// Pattern: time="2024-01-15T10:30:00Z" level=info msg="Request" ip=1.2.3.4 host=example.com
	logfmtPattern = regexp.MustCompile(`(?:ip|clientIP|client_ip)=["']?([0-9a-fA-F.:]+)["']?`)
	hostPattern   = regexp.MustCompile(`(?:host|hostname)=["']?([a-zA-Z0-9.-]+)["']?`)
	pathPattern   = regexp.MustCompile(`(?:path|uri|url)=["']?([^\s"']+)["']?`)
	methodPattern = regexp.MustCompile(`(?:method)=["']?([A-Z]+)["']?`)
)

type LogParser struct {
	db      *sql.DB
	verbose bool
}

func main() {
	dbPath := flag.String("db", "/data/connections.db", "Path to SQLite database")
	logFile := flag.String("file", "", "Log file to tail (reads stdin if not specified)")
	verbose := flag.Bool("verbose", false, "Verbose output")
	flag.Parse()

	// Open database
	db, err := sql.Open("sqlite3", *dbPath+"?_journal_mode=WAL")
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	defer db.Close()

	// Ensure table exists
	if err := initDB(db); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	parser := &LogParser{db: db, verbose: *verbose}

	// Read from file or stdin
	var scanner *bufio.Scanner
	if *logFile != "" {
		file, err := os.Open(*logFile)
		if err != nil {
			log.Fatalf("Failed to open log file: %v", err)
		}
		defer file.Close()
		scanner = bufio.NewScanner(file)
		log.Printf("Reading from file: %s", *logFile)
	} else {
		scanner = bufio.NewScanner(os.Stdin)
		log.Println("Reading from stdin...")
	}

	// Increase buffer size for long log lines
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 1024*1024)

	log.Println("Cloudflared log parser started")

	for scanner.Scan() {
		line := scanner.Text()
		parser.processLine(line)
	}

	if err := scanner.Err(); err != nil {
		log.Fatalf("Error reading input: %v", err)
	}
}

func initDB(db *sql.DB) error {
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
	CREATE INDEX IF NOT EXISTS idx_host ON connections(host);
	`
	_, err := db.Exec(schema)
	return err
}

func (p *LogParser) processLine(line string) {
	if line == "" {
		return
	}

	// Try JSON first
	if strings.HasPrefix(strings.TrimSpace(line), "{") {
		p.parseJSON(line)
		return
	}

	// Fall back to regex parsing
	p.parseLogfmt(line)
}

func (p *LogParser) parseJSON(line string) {
	var entry CloudflaredLogEntry
	if err := json.Unmarshal([]byte(line), &entry); err != nil {
		if p.verbose {
			log.Printf("Failed to parse JSON: %v", err)
		}
		return
	}

	// Extract client IP from various possible fields
	clientIP := entry.ClientIP
	if clientIP == "" {
		clientIP = entry.IP
	}

	// Skip if no useful request info
	if clientIP == "" && entry.Hostname == "" {
		// Check if it's a request-related message
		msg := entry.Message
		if msg == "" {
			msg = entry.Msg
		}
		if !strings.Contains(strings.ToLower(msg), "request") &&
			!strings.Contains(strings.ToLower(msg), "http") {
			return
		}
	}

	// Skip internal/infrastructure messages
	msg := entry.Message
	if msg == "" {
		msg = entry.Msg
	}
	if strings.Contains(msg, "Registered tunnel connection") ||
		strings.Contains(msg, "Initial protocol") ||
		strings.Contains(msg, "Connection established") {
		if p.verbose {
			log.Printf("Skipping infrastructure log: %s", msg)
		}
		return
	}

	// Only log if we have at least an IP or hostname
	if clientIP == "" && entry.Hostname == "" && entry.Origin == "" {
		return
	}

	// Parse timestamp
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	if entry.Time != "" {
		if t, err := time.Parse(time.RFC3339, entry.Time); err == nil {
			timestamp = t.Local().Format("2006-01-02 15:04:05")
		}
	}

	// Extract hostname from origin URL if not set
	hostname := entry.Hostname
	if hostname == "" && entry.Origin != "" {
		hostname = extractHostFromURL(entry.Origin)
	}

	// Extract path
	path := entry.Path
	if path == "" && entry.Origin != "" {
		path = extractPathFromURL(entry.Origin)
	}

	method := entry.Method
	if method == "" {
		method = "GET"
	}

	p.insertConnection(timestamp, clientIP, "", method, path, hostname, "", "")
}

func (p *LogParser) parseLogfmt(line string) {
	// Extract fields using regex
	var clientIP, hostname, path, method string

	if matches := logfmtPattern.FindStringSubmatch(line); len(matches) > 1 {
		clientIP = matches[1]
	}
	if matches := hostPattern.FindStringSubmatch(line); len(matches) > 1 {
		hostname = matches[1]
	}
	if matches := pathPattern.FindStringSubmatch(line); len(matches) > 1 {
		path = matches[1]
	}
	if matches := methodPattern.FindStringSubmatch(line); len(matches) > 1 {
		method = matches[1]
	}

	// Skip if no useful info
	if clientIP == "" && hostname == "" {
		return
	}

	if method == "" {
		method = "GET"
	}

	timestamp := time.Now().Format("2006-01-02 15:04:05")
	p.insertConnection(timestamp, clientIP, "", method, path, hostname, "", "")
}

func (p *LogParser) insertConnection(timestamp, clientIP, country, method, path, host, userAgent, referer string) {
	_, err := p.db.Exec(`
		INSERT INTO connections (timestamp, client_ip, country, method, path, host, user_agent, referer)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		timestamp, clientIP, country, method, path, host, userAgent, referer)
	
	if err != nil {
		log.Printf("Failed to insert: %v", err)
		return
	}

	log.Printf("Logged: %s | %s | %s %s | %s", timestamp, clientIP, method, path, host)
}

func extractHostFromURL(url string) string {
	// Remove protocol
	url = strings.TrimPrefix(url, "http://")
	url = strings.TrimPrefix(url, "https://")
	// Get host part
	if idx := strings.Index(url, "/"); idx != -1 {
		url = url[:idx]
	}
	if idx := strings.Index(url, ":"); idx != -1 {
		url = url[:idx]
	}
	return url
}

func extractPathFromURL(url string) string {
	// Remove protocol
	url = strings.TrimPrefix(url, "http://")
	url = strings.TrimPrefix(url, "https://")
	// Get path part
	if idx := strings.Index(url, "/"); idx != -1 {
		return url[idx:]
	}
	return "/"
}
