#!/usr/bin/env bash
# =============================================================================
# pull-images.sh — Pull all development images into Podman
# =============================================================================
# Usage:
#   ./scripts/pull-images.sh            — pull all images
#   ./scripts/pull-images.sh databases  — pull only a category
#
# Categories:
#   databases | brokers | webservers | devtools | observability |
#   auth | testing | cicd | runtimes | all (default)
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*"; }

PULLED=0
FAILED=0
SKIPPED=0

pull_image() {
  local image="$1"
  local label="$2"

  echo -ne "  Pulling ${BOLD}${label}${RESET} (${image}) ... "

  if podman image exists "$image" 2>/dev/null; then
    echo -e "${YELLOW}already exists, skipping${RESET}"
    ((SKIPPED++)) || true
    return
  fi

  if podman pull "$image" > /dev/null 2>&1; then
    echo -e "${GREEN}done${RESET}"
    ((PULLED++)) || true
  else
    echo -e "${RED}FAILED${RESET}"
    warn "Could not pull $image — skipping"
    ((FAILED++)) || true
  fi
}

section() {
  echo ""
  echo -e "${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ── Image Lists ───────────────────────────────────────────────────────────────

pull_databases() {
  section "🗄️  Databases"
  pull_image "docker.io/postgres:16"            "PostgreSQL 16"
  pull_image "docker.io/mysql:8"                "MySQL 8"
  pull_image "docker.io/mariadb:11"             "MariaDB 11"
  pull_image "docker.io/mongo:7"                "MongoDB 7"
  pull_image "docker.io/redis:7"                "Redis 7"
  pull_image "docker.io/elasticsearch:8.12.0"   "Elasticsearch 8"
  pull_image "docker.io/influxdb:2"             "InfluxDB 2"
  pull_image "docker.io/neo4j:5"                "Neo4j 5"
  pull_image "docker.io/couchdb:3"              "CouchDB 3"
}

pull_brokers() {
  section "📨  Message Brokers & Queues"
  pull_image "docker.io/rabbitmq:3-management"              "RabbitMQ 3 + Management UI"
  pull_image "docker.io/confluentinc/cp-zookeeper:latest"   "Confluent Zookeeper"
  pull_image "docker.io/confluentinc/cp-kafka:latest"       "Confluent Kafka"
  pull_image "docker.io/nats:latest"                        "NATS"
}

pull_webservers() {
  section "🌐  Web Servers & Proxies"
  pull_image "docker.io/nginx:alpine"      "NGINX Alpine"
  pull_image "docker.io/caddy:latest"      "Caddy"
  pull_image "docker.io/traefik:v3"        "Traefik v3"
  pull_image "docker.io/haproxy:alpine"    "HAProxy Alpine"
}

pull_devtools() {
  section "🛠️  Dev Tools & Utilities"
  pull_image "docker.io/mailhog/mailhog:latest"         "MailHog"
  pull_image "docker.io/minio/minio:latest"             "MinIO"
  pull_image "docker.io/localstack/localstack:latest"   "LocalStack (AWS)"
  pull_image "docker.io/wiremock/wiremock:latest"       "WireMock"
  pull_image "docker.io/verdaccio/verdaccio:latest"     "Verdaccio (npm registry)"
}

pull_observability() {
  section "📊  Observability & Monitoring"
  pull_image "docker.io/grafana/grafana:latest"          "Grafana"
  pull_image "docker.io/prom/prometheus:latest"          "Prometheus"
  pull_image "docker.io/jaegertracing/all-in-one:latest" "Jaeger"
  pull_image "docker.io/openzipkin/zipkin:latest"        "Zipkin"
  pull_image "docker.io/grafana/loki:latest"             "Loki"
  pull_image "docker.io/kibana:8.12.0"                   "Kibana 8"
}

pull_auth() {
  section "🔐  Auth & Identity"
  pull_image "docker.io/keycloak/keycloak:latest"   "Keycloak"
  pull_image "docker.io/dexidp/dex:latest"          "Dex"
  pull_image "docker.io/hashicorp/vault:latest"     "Vault"
}

pull_testing() {
  section "🧪  Testing & QA"
  pull_image "docker.io/selenium/standalone-chrome:latest"   "Selenium Chrome"
  pull_image "docker.io/sonarsource/sonarqube:community"     "SonarQube Community"
}

pull_cicd() {
  section "📦  CI/CD & Container Tooling"
  pull_image "docker.io/jenkins/jenkins:lts"            "Jenkins LTS"
  pull_image "docker.io/gitea/gitea:latest"             "Gitea"
  pull_image "docker.io/portainer/portainer-ce:latest"  "Portainer CE"
}

pull_runtimes() {
  section "🧬  Language Runtimes"
  pull_image "docker.io/node:lts"                            "Node.js LTS"
  pull_image "docker.io/node:25"                             "Node.js 25"
  pull_image "docker.io/python:3.13"                         "Python 3.13"
  pull_image "docker.io/python:3.13-slim"                    "Python 3.13 Slim"
  pull_image "docker.io/rust:latest"                         "Rust latest"
  pull_image "docker.io/golang:1.23"                         "Go 1.23"
  pull_image "docker.io/eclipse-temurin:21"                  "Java 21 (Temurin)"
  pull_image "docker.io/php:8.3-fpm"                         "PHP 8.3 FPM"
  pull_image "docker.io/ruby:3.3"                            "Ruby 3.3"
  pull_image "mcr.microsoft.com/dotnet/sdk:8.0"              ".NET SDK 8"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}━━━ Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "  ${GREEN}Pulled:${RESET}  $PULLED"
  echo -e "  ${YELLOW}Skipped:${RESET} $SKIPPED (already present)"
  echo -e "  ${RED}Failed:${RESET}  $FAILED"
  echo ""
  if [[ $FAILED -gt 0 ]]; then
    warn "Some images failed — check your internet connection or image names."
  else
    success "All images ready!"
  fi

  echo ""
  log "To list all pulled images:"
  echo "    podman images"
  echo ""
  log "To start a stack:"
  echo "    cd stacks/web-api && podman compose up -d"
}

# ── Entry Point ───────────────────────────────────────────────────────────────
CATEGORY="${1:-all}"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Podman Dev Stacks — Image Puller         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""
log "Category: ${BOLD}${CATEGORY}${RESET}"

case "$CATEGORY" in
  databases)    pull_databases ;;
  brokers)      pull_brokers ;;
  webservers)   pull_webservers ;;
  devtools)     pull_devtools ;;
  observability) pull_observability ;;
  auth)         pull_auth ;;
  testing)      pull_testing ;;
  cicd)         pull_cicd ;;
  runtimes)     pull_runtimes ;;
  all)
    pull_databases
    pull_brokers
    pull_webservers
    pull_devtools
    pull_observability
    pull_auth
    pull_testing
    pull_cicd
    pull_runtimes
    ;;
  *)
    error "Unknown category: $CATEGORY"
    echo ""
    echo "Available categories:"
    echo "  databases | brokers | webservers | devtools | observability"
    echo "  auth | testing | cicd | runtimes | all"
    exit 1
    ;;
esac

print_summary
