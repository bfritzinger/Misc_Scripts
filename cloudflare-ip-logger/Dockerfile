# Build stage
FROM golang:1.21-bookworm AS builder

WORKDIR /build

# Install SQLite dependencies for CGO
RUN apt-get update && apt-get install -y gcc libsqlite3-dev

COPY go.mod go.sum* ./
RUN go mod download

COPY *.go ./

RUN go mod tidy

# Build main app
RUN CGO_ENABLED=1 go build -ldflags="-s -w" -o cf-ip-logger .

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsqlite3-0 \
    tzdata \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/cf-ip-logger .

# Create data directory
RUN mkdir -p /data

ENV DATA_DIR=/data
ENV PORT=8080

EXPOSE 8080

VOLUME ["/data"]

CMD ["./cf-ip-logger"]
