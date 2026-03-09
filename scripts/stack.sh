#!/usr/bin/env bash
# =============================================================================
# stack.sh — Manage dev stacks (start, stop, status, clean)
# =============================================================================
# Usage:
#   ./scripts/stack.sh <command> [stack]
#
# Commands:
#   up    [stack]   — start a stack (or all)
#   down  [stack]   — stop a stack (or all), data preserved
#   clean [stack]   — stop + remove volumes
#   ps              — show all running containers
#   logs  <stack>   — follow logs for a stack
#
# Examples:
#   ./scripts/stack.sh up web-api
#   ./scripts/stack.sh down microservices
#   ./scripts/stack.sh ps
#   ./scripts/stack.sh clean web-api
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STACKS_DIR="$REPO_ROOT/stacks"

ALL_STACKS=("web-api" "microservices" "devops" "cloud-local" "data-ml")

run_stack() {
  local cmd="$1"
  local stack="$2"
  local compose_file="$STACKS_DIR/$stack/compose.yml"

  [[ ! -f "$compose_file" ]] && error "No compose.yml found for stack: $stack"

  log "${cmd} → ${BOLD}$stack${RESET}"
  pushd "$STACKS_DIR/$stack" > /dev/null
  podman compose $cmd
  popd > /dev/null
}

[[ $# -lt 1 ]] && error "Usage: $0 <up|down|clean|ps|logs> [stack]"

CMD="$1"
STACK="${2:-}"

case "$CMD" in
  up)
    if [[ -n "$STACK" ]]; then
      run_stack "up -d" "$STACK"
      success "$STACK started"
    else
      for s in "${ALL_STACKS[@]}"; do
        run_stack "up -d" "$s"
      done
      success "All stacks started"
    fi
    ;;

  down)
    if [[ -n "$STACK" ]]; then
      run_stack "down" "$STACK"
      success "$STACK stopped (data preserved)"
    else
      for s in "${ALL_STACKS[@]}"; do
        run_stack "down" "$s"
      done
      success "All stacks stopped"
    fi
    ;;

  clean)
    if [[ -n "$STACK" ]]; then
      warn "This will delete all volumes for: $STACK"
      read -p "Are you sure? [y/N] " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
      run_stack "down -v" "$STACK"
      success "$STACK cleaned"
    else
      warn "This will delete ALL volumes for ALL stacks!"
      read -p "Are you sure? [y/N] " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
      for s in "${ALL_STACKS[@]}"; do
        run_stack "down -v" "$s"
      done
      success "All stacks cleaned"
    fi
    ;;

  ps)
    echo ""
    echo -e "${BOLD}Running containers:${RESET}"
    echo ""
    podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    ;;

  logs)
    [[ -z "$STACK" ]] && error "Usage: $0 logs <stack>"
    pushd "$STACKS_DIR/$STACK" > /dev/null
    podman compose logs -f
    popd > /dev/null
    ;;

  *)
    error "Unknown command: $CMD. Use: up | down | clean | ps | logs"
    ;;
esac
