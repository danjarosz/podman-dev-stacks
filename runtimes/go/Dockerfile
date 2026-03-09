# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM docker.io/golang:1.23 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o app ./cmd/main.go


# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM scratch AS runtime

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/app /app

EXPOSE 8080
CMD ["/app"]
