#!/usr/bin/env bash
# =============================================================================
# update-images.sh — Check and update Podman dev images to their latest versions
# =============================================================================
# Usage:
#   ./scripts/update-images.sh               — update all images
#   ./scripts/update-images.sh databases     — update only a category
#   ./scripts/update-images.sh --check       — dry run, show what would update
#   ./scripts/update-images.sh --prune       — also remove old/dangling images after update
#   ./scripts/update-images.sh --list        — list all locally present dev images
#
# Categories:
#   databases | brokers | webservers | devtools | observability |
#   auth | testing | cicd | runtimes | all (default)
#
# How it works:
#   For each image, the script compares the local image digest against the
#   remote registry digest. If they differ, the image is outdated and gets
#   re-pulled. Images not present locally are skipped (use pull-images.sh first).
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${CYAN}${BOLD}[INFO]${RESET}   $*"; }
success() { echo -e "${GREEN}${BOLD}[UP-TO-DATE]${RESET} $*"; }
updated() { echo -e "${BLUE}${BOLD}[UPDATED]${RESET}    $*"; }
skipped() { echo -e "${YELLOW}${BOLD}[SKIPPED]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}   $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET}  $*"; }

# ── Counters ──────────────────────────────────────────────────────────────────
COUNT_UPDATED=0
COUNT_CURRENT=0
COUNT_SKIPPED=0
COUNT_FAILED=0
COUNT_CHECKED=0

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
DO_PRUNE=false
DO_LIST=false
CATEGORY="all"
LOG_FILE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   DRY_RUN=true; shift ;;
    --prune)   DO_PRUNE=true; shift ;;
    --list)    DO_LIST=true; shift ;;
    --log)     LOG_FILE="$2"; shift 2 ;;
    --help)
      echo ""
      echo "Usage: update-images.sh [category] [options]"
      echo ""
      echo "Categories:  databases | brokers | webservers | devtools | observability"
      echo "             auth | testing | cicd | runtimes | all (default)"
      echo ""
      echo "Options:"
      echo "  --check    Dry run — show what would be updated without pulling"
      echo "  --prune    Remove dangling/old images after updating"
      echo "  --list     List all locally present dev images and exit"
      echo "  --log FILE Write update report to a file"
      echo "  --help     Show this help"
      echo ""
      echo "Examples:"
      echo "  update-images.sh                   # update everything"
      echo "  update-images.sh databases         # update only databases"
      echo "  update-images.sh runtimes --prune  # update runtimes, clean up old layers"
      echo "  update-images.sh --check           # see what's outdated without pulling"
      echo "  update-images.sh --list            # show all local dev images"
      exit 0
      ;;
    -*)
      warn "Unknown option: $1 (ignoring)"
      shift
      ;;
    *)
      CATEGORY="$1"
      shift
      ;;
  esac
done

# ── Image registry ────────────────────────────────────────────────────────────
# Format: "image:tag|Human Label"
declare -a IMAGES_DATABASES=(
  "docker.io/postgres:16|PostgreSQL 16"
  "docker.io/mysql:8|MySQL 8"
  "docker.io/mariadb:11|MariaDB 11"
  "docker.io/mongo:7|MongoDB 7"
  "docker.io/redis:7|Redis 7"
  "docker.io/elasticsearch:8.12.0|Elasticsearch 8"
  "docker.io/influxdb:2|InfluxDB 2"
  "docker.io/neo4j:5|Neo4j 5"
  "docker.io/couchdb:3|CouchDB 3"
)

declare -a IMAGES_BROKERS=(
  "docker.io/rabbitmq:3-management|RabbitMQ 3 + Management UI"
  "docker.io/confluentinc/cp-zookeeper:latest|Confluent Zookeeper"
  "docker.io/confluentinc/cp-kafka:latest|Confluent Kafka"
  "docker.io/nats:latest|NATS"
)

declare -a IMAGES_WEBSERVERS=(
  "docker.io/nginx:alpine|NGINX Alpine"
  "docker.io/caddy:latest|Caddy"
  "docker.io/traefik:v3|Traefik v3"
  "docker.io/haproxy:alpine|HAProxy Alpine"
)

declare -a IMAGES_DEVTOOLS=(
  "docker.io/mailhog/mailhog:latest|MailHog"
  "docker.io/minio/minio:latest|MinIO"
  "docker.io/localstack/localstack:latest|LocalStack"
  "docker.io/wiremock/wiremock:latest|WireMock"
  "docker.io/verdaccio/verdaccio:latest|Verdaccio"
)

declare -a IMAGES_OBSERVABILITY=(
  "docker.io/grafana/grafana:latest|Grafana"
  "docker.io/prom/prometheus:latest|Prometheus"
  "docker.io/jaegertracing/all-in-one:latest|Jaeger"
  "docker.io/openzipkin/zipkin:latest|Zipkin"
  "docker.io/grafana/loki:latest|Loki"
  "docker.io/kibana:8.12.0|Kibana 8"
)

declare -a IMAGES_AUTH=(
  "docker.io/keycloak/keycloak:latest|Keycloak"
  "docker.io/dexidp/dex:latest|Dex"
  "docker.io/hashicorp/vault:latest|Vault"
)

declare -a IMAGES_TESTING=(
  "docker.io/selenium/standalone-chrome:latest|Selenium Chrome"
  "docker.io/sonarsource/sonarqube:community|SonarQube Community"
)

declare -a IMAGES_CICD=(
  "docker.io/jenkins/jenkins:lts|Jenkins LTS"
  "docker.io/gitea/gitea:latest|Gitea"
  "docker.io/portainer/portainer-ce:latest|Portainer CE"
)

declare -a IMAGES_RUNTIMES=(
  "docker.io/node:lts|Node.js LTS"
  "docker.io/node:25|Node.js 25"
  "docker.io/python:3.13|Python 3.13"
  "docker.io/python:3.13-slim|Python 3.13 Slim"
  "docker.io/rust:latest|Rust latest"
  "docker.io/golang:1.23|Go 1.23"
  "docker.io/eclipse-temurin:21|Java 21 (Temurin)"
  "docker.io/php:8.3-fpm|PHP 8.3 FPM"
  "docker.io/ruby:3.3|Ruby 3.3"
  "mcr.microsoft.com/dotnet/sdk:8.0|.NET SDK 8"
)

# ── List local images ─────────────────────────────────────────────────────────
list_local_images() {
  echo ""
  echo -e "${BOLD}Locally present dev images:${RESET}"
  echo ""
  printf "  %-55s %-12s %s\n" "IMAGE" "SIZE" "CREATED"
  printf "  %-55s %-12s %s\n" "─────────────────────────────────────────────────────" "────────────" "──────────────"

  local all_images=(
    "${IMAGES_DATABASES[@]}"
    "${IMAGES_BROKERS[@]}"
    "${IMAGES_WEBSERVERS[@]}"
    "${IMAGES_DEVTOOLS[@]}"
    "${IMAGES_OBSERVABILITY[@]}"
    "${IMAGES_AUTH[@]}"
    "${IMAGES_TESTING[@]}"
    "${IMAGES_CICD[@]}"
    "${IMAGES_RUNTIMES[@]}"
  )

  local found=0
  for entry in "${all_images[@]}"; do
    local image="${entry%%|*}"
    if podman image exists "$image" 2>/dev/null; then
      local size created
      size=$(podman image inspect "$image" --format "{{.Size}}" 2>/dev/null | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "unknown")
      created=$(podman image inspect "$image" --format "{{.Created}}" 2>/dev/null | cut -d'T' -f1 || echo "unknown")
      printf "  %-55s %-12s %s\n" "$image" "$size" "$created"
      ((found++)) || true
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "  No dev images found locally. Run pull-images.sh first."
  else
    echo ""
    echo -e "  ${GREEN}${found} images found locally${RESET}"
  fi
  echo ""
}

# ── Core update logic ─────────────────────────────────────────────────────────
UPDATED_IMAGES=()   # track names for the report

check_and_update() {
  local image="$1"
  local label="$2"

  ((COUNT_CHECKED++)) || true

  # Skip if not present locally — user should use pull-images.sh first
  if ! podman image exists "$image" 2>/dev/null; then
    echo -e "  ${YELLOW}○${RESET} ${BOLD}${label}${RESET} — not installed locally, skipping"
    ((COUNT_SKIPPED++)) || true
    return
  fi

  echo -ne "  ${BOLD}${label}${RESET} (${image}) ... "

  # Get local digest
  local local_digest
  local_digest=$(podman image inspect "$image" --format "{{.Digest}}" 2>/dev/null || echo "")

  # Get remote digest without pulling
  local remote_digest
  remote_digest=$(podman image search "$image" --list-tags 2>/dev/null | head -1 || echo "")

  # Use skopeo if available for accurate digest comparison — fall back to pull attempt
  if command -v skopeo &>/dev/null; then
    remote_digest=$(skopeo inspect "docker://${image}" --format "{{.Digest}}" 2>/dev/null || echo "unknown")
  else
    # Without skopeo: always attempt pull and check if podman reports "up to date"
    remote_digest="unknown"
  fi

  if [[ "$remote_digest" != "unknown" && "$local_digest" == "$remote_digest" ]]; then
    echo -e "${GREEN}up to date${RESET}"
    ((COUNT_CURRENT++)) || true
    return
  fi

  # Either digests differ, or we couldn't compare — attempt pull
  if $DRY_RUN; then
    echo -e "${BLUE}would update${RESET}"
    ((COUNT_UPDATED++)) || true
    UPDATED_IMAGES+=("$label ($image)")
    return
  fi

  # Pull and detect if anything actually changed
  local pull_output
  pull_output=$(podman pull "$image" 2>&1) || {
    echo -e "${RED}FAILED${RESET}"
    warn "Could not pull $image"
    ((COUNT_FAILED++)) || true
    return
  }

  if echo "$pull_output" | grep -q "Writing manifest\|Storing signatures\|Downloaded newer"; then
    echo -e "${BLUE}updated ✓${RESET}"
    ((COUNT_UPDATED++)) || true
    UPDATED_IMAGES+=("$label ($image)")
  else
    echo -e "${GREEN}already up to date${RESET}"
    ((COUNT_CURRENT++)) || true
  fi
}

# ── Process a category ────────────────────────────────────────────────────────
process_category() {
  local title="$1"
  shift
  local images=("$@")

  echo ""
  echo -e "${BOLD}━━━ ${title} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  for entry in "${images[@]}"; do
    local image="${entry%%|*}"
    local label="${entry##*|}"
    check_and_update "$image" "$label"
  done
}

# ── Prune old images ──────────────────────────────────────────────────────────
prune_images() {
  echo ""
  echo -e "${BOLD}━━━ Pruning old/dangling images ━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  local before after freed
  before=$(podman system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0")

  log "Removing dangling images (unreferenced layers)..."
  podman image prune -f 2>/dev/null && success "Dangling images removed" || warn "Nothing to prune"

  after=$(podman system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0")

  echo ""
  log "To also remove all unused images (not just dangling):"
  echo "    podman image prune -a -f"
  echo ""
  log "To see full disk usage:"
  echo "    podman system df"
}

# ── Write log file ────────────────────────────────────────────────────────────
write_log() {
  [[ -z "$LOG_FILE" ]] && return

  {
    echo "# Podman Dev Stacks — Update Report"
    echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Category: $CATEGORY"
    echo ""
    echo "## Summary"
    echo "  Checked:     $COUNT_CHECKED"
    echo "  Updated:     $COUNT_UPDATED"
    echo "  Up to date:  $COUNT_CURRENT"
    echo "  Skipped:     $COUNT_SKIPPED"
    echo "  Failed:      $COUNT_FAILED"
    echo ""
    if [[ ${#UPDATED_IMAGES[@]} -gt 0 ]]; then
      echo "## Updated images"
      for img in "${UPDATED_IMAGES[@]}"; do
        echo "  - $img"
      done
    fi
  } > "$LOG_FILE"

  log "Report written to: ${BOLD}$LOG_FILE${RESET}"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}━━━ Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  printf "  %-20s %s\n" "Checked:"    "$COUNT_CHECKED"
  printf "  %-20s ${BLUE}%s${RESET}\n" "Updated:"    "$COUNT_UPDATED"
  printf "  %-20s ${GREEN}%s${RESET}\n" "Up to date:" "$COUNT_CURRENT"
  printf "  %-20s ${YELLOW}%s${RESET}\n" "Skipped:"    "$COUNT_SKIPPED (not installed)"
  printf "  %-20s ${RED}%s${RESET}\n" "Failed:"     "$COUNT_FAILED"
  echo ""

  if [[ ${#UPDATED_IMAGES[@]} -gt 0 ]]; then
    echo -e "${BOLD}Updated images:${RESET}"
    for img in "${UPDATED_IMAGES[@]}"; do
      echo -e "  ${BLUE}↑${RESET} $img"
    done
    echo ""
  fi

  if $DRY_RUN; then
    echo -e "${YELLOW}${BOLD}Dry run — nothing was actually pulled.${RESET}"
    echo -e "Remove ${BOLD}--check${RESET} to apply updates."
    echo ""
  fi

  if [[ $COUNT_SKIPPED -gt 0 ]]; then
    log "To install skipped images:"
    echo "    pull-images.sh [category]"
    echo ""
  fi

  if [[ $COUNT_FAILED -gt 0 ]]; then
    warn "Some updates failed — check your network connection."
    echo ""
  fi

  if [[ $COUNT_UPDATED -eq 0 && $COUNT_FAILED -eq 0 && ! $DRY_RUN ]]; then
    echo -e "${GREEN}${BOLD}Everything is up to date!${RESET}"
    echo ""
  fi
}

# ── Entry Point ───────────────────────────────────────────────────────────────

# Handle --list before banner
if $DO_LIST; then
  list_local_images
  exit 0
fi

# Banner
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Podman Dev Stacks — Image Updater            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""

if $DRY_RUN; then
  warn "Dry run mode — showing what would update, not pulling anything"
fi

if command -v skopeo &>/dev/null; then
  log "skopeo found — using precise digest comparison"
else
  warn "skopeo not found — will pull each image and detect changes from output"
  log "Install skopeo for faster, network-efficient checks:"
  echo "    Ubuntu/Debian: sudo apt install skopeo"
  echo "    Fedora/RHEL:   sudo dnf install skopeo"
  echo "    macOS:         brew install skopeo"
  echo ""
fi

log "Category: ${BOLD}${CATEGORY}${RESET}"

case "$CATEGORY" in
  databases)     process_category "🗄️  Databases"              "${IMAGES_DATABASES[@]}" ;;
  brokers)       process_category "📨  Brokers & Queues"        "${IMAGES_BROKERS[@]}" ;;
  webservers)    process_category "🌐  Web Servers & Proxies"   "${IMAGES_WEBSERVERS[@]}" ;;
  devtools)      process_category "🛠️  Dev Tools"               "${IMAGES_DEVTOOLS[@]}" ;;
  observability) process_category "📊  Observability"           "${IMAGES_OBSERVABILITY[@]}" ;;
  auth)          process_category "🔐  Auth & Identity"         "${IMAGES_AUTH[@]}" ;;
  testing)       process_category "🧪  Testing & QA"            "${IMAGES_TESTING[@]}" ;;
  cicd)          process_category "📦  CI/CD Tooling"           "${IMAGES_CICD[@]}" ;;
  runtimes)      process_category "🧬  Language Runtimes"       "${IMAGES_RUNTIMES[@]}" ;;
  all)
    process_category "🗄️  Databases"              "${IMAGES_DATABASES[@]}"
    process_category "📨  Brokers & Queues"        "${IMAGES_BROKERS[@]}"
    process_category "🌐  Web Servers & Proxies"   "${IMAGES_WEBSERVERS[@]}"
    process_category "🛠️  Dev Tools"               "${IMAGES_DEVTOOLS[@]}"
    process_category "📊  Observability"           "${IMAGES_OBSERVABILITY[@]}"
    process_category "🔐  Auth & Identity"         "${IMAGES_AUTH[@]}"
    process_category "🧪  Testing & QA"            "${IMAGES_TESTING[@]}"
    process_category "📦  CI/CD Tooling"           "${IMAGES_CICD[@]}"
    process_category "🧬  Language Runtimes"       "${IMAGES_RUNTIMES[@]}"
    ;;
  *)
    error "Unknown category: $CATEGORY"
    echo ""
    echo "Valid categories: databases | brokers | webservers | devtools |"
    echo "                  observability | auth | testing | cicd | runtimes | all"
    exit 1
    ;;
esac

if $DO_PRUNE; then
  prune_images
fi

print_summary
write_log
