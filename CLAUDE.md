# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This repo is a *collection of independent utility scripts*, not a single application. Each top-level directory is a self-contained tool with its own README and (usually) a single entry-point script. There is no shared library, no top-level build, no test suite, and no package manifest at the root. Treat each subdirectory as its own micro-project.

The only compiled component is `cloudflare-ip-logger/` (Go + SQLite, shipped as a Docker image). Everything else is bash or Python.

## Conventions for adding/modifying scripts

- New scripts start by copying `_template/` and renaming it. The template's `README.md` defines the documentation shape every tool follows (Overview / Prerequisites / Installation / Usage / Options table / Configuration table / How It Works / Troubleshooting / Changelog).
- After adding a new script directory, update the script table in the top-level `README.md` — the table is the canonical index and is expected to stay in sync with the directory listing.
- Bash scripts use `#!/usr/bin/env bash` (preferred) or `#!/bin/bash`. Several of the larger scripts (`HealthCheck`, `LinuxTroubleshooting`, `chown_throttled`, `File_retention`) carry a banner header comment with name + version — match that style when editing them.
- Python scripts target Python 3 and are written to be stdlib-only (no `requirements.txt` anywhere). Don't introduce third-party deps without flagging it; the "no external dependencies" property is called out explicitly in several READMEs (`dirsync`, `LinuxTroubleshooting`).
- Some directories use kebab-case (`cluster-ssh-key-setup`, `git-update`), others CamelCase (`HealthCheck`, `HungConnections`, `LinuxTroubleshooting`, `File_retention`). Don't rename existing ones — the README table links to them by name.

## cloudflare-ip-logger (the one non-script component)

A Go reverse proxy that sits behind `cloudflared` to capture real visitor IPs from the `CF-Connecting-IP` header before forwarding to backend services. Runs as a Docker container.

- `main.go` — the proxy + REST API + dashboard server. Routes by `Host` header against `proxy-config.json`, persists to SQLite, also tails to a plain-text log.
- `cmd/logparser/main.go` — separate binary that parses `cloudflared`'s JSON logs and ingests them into the same SQLite DB. Used by `run-with-logging.sh` and the `cf-log-parser.service` systemd unit when running cloudflared alongside the logger.
- Build/run: `docker compose up -d --build` from the directory. The Dockerfile uses CGO (required by `mattn/go-sqlite3`), so cross-compilation needs the C toolchain.
- Data layout under `/data` (volume-mounted): `connections.db`, `connections.log`, `proxy-config.json`. The example config lives at `proxy-config.json.example` in the repo and is copied into the data dir on first run.
- Routing depends on cloudflared preserving the original `Host` header via `originRequest.httpHostHeader` — this is the most common misconfiguration, see the README's "Cloudflared Configuration" section.

## Things that look like patterns but aren't

- There is no shared bash helper library. Logging/colors/error-handling are reimplemented per-script. Don't try to refactor across scripts unless the user asks.
- `pwr-temp-monitor/` ships several `*_metrics.sh` scripts (pi/jetson/x86) that look similar but target different hardware — they're meant to be deployed selectively by `setup.sh`, not unified.
- `HungConnections/` intentionally has both `.sh` and `.py` implementations of the same tool. Keep them feature-equivalent if you change one.
