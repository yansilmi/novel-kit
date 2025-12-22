#!/usr/bin/env bash

set -e

# Find repository root
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.novelkit" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT="$(find_repo_root "$(pwd)")"
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Could not find repository root" >&2
    exit 1
fi

CONSTITUTION_DIR="$REPO_ROOT/.novelkit/memory"
CONSTITUTION_FILE="$CONSTITUTION_DIR/constitution.md"
TEMPLATE_FILE="$REPO_ROOT/.novelkit/templates/constitution.md"

# Ensure directories exist
mkdir -p "$CONSTITUTION_DIR"

# JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "create")
            cat <<EOF
{
  "action": "create",
  "success": true,
  "constitution_file": "$CONSTITUTION_FILE",
  "template_file": "$TEMPLATE_FILE",
  "exists": $([ -f "$CONSTITUTION_FILE" ] && echo "true" || echo "false")
}
EOF
            ;;
        "show")
            if [ -f "$CONSTITUTION_FILE" ]; then
                cat <<EOF
{
  "action": "show",
  "success": true,
  "constitution_file": "$CONSTITUTION_FILE",
  "exists": true
}
EOF
            else
                echo "{\"action\":\"show\",\"success\":false,\"error\":\"Constitution not found\"}" >&2
                exit 1
            fi
            ;;
        "update")
            if [ -f "$CONSTITUTION_FILE" ]; then
                cat <<EOF
{
  "action": "update",
  "success": true,
  "constitution_file": "$CONSTITUTION_FILE",
  "exists": true
}
EOF
            else
                echo "{\"action\":\"update\",\"success\":false,\"error\":\"Constitution not found. Create it first.\"}" >&2
                exit 1
            fi
            ;;
        "check")
            cat <<EOF
{
  "action": "check",
  "success": true,
  "constitution_file": "$CONSTITUTION_FILE",
  "exists": $([ -f "$CONSTITUTION_FILE" ] && echo "true" || echo "false")
}
EOF
            ;;
    esac
}

# Action handlers
action_create() {
    # Check if already exists
    if [ -f "$CONSTITUTION_FILE" ]; then
        echo "{\"action\":\"create\",\"success\":false,\"error\":\"Constitution already exists. Use update command instead.\",\"constitution_file\":\"$CONSTITUTION_FILE\"}" >&2
        exit 1
    fi
    
    json_output "create"
}

action_show() {
    if [ ! -f "$CONSTITUTION_FILE" ]; then
        echo "{\"action\":\"show\",\"success\":false,\"error\":\"Constitution not found. Use create command first.\"}" >&2
        exit 1
    fi
    
    json_output "show"
}

action_update() {
    if [ ! -f "$CONSTITUTION_FILE" ]; then
        echo "{\"action\":\"update\",\"success\":false,\"error\":\"Constitution not found. Use create command first.\"}" >&2
        exit 1
    fi
    
    json_output "update"
}

action_check() {
    if [ ! -f "$CONSTITUTION_FILE" ]; then
        echo "{\"action\":\"check\",\"success\":false,\"error\":\"Constitution not found. Use create command first.\"}" >&2
        exit 1
    fi
    
    json_output "check"
}

# Main script
JSON_MODE=false
ACTION=""
ARGS=()

# Parse arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        create|show|update|check)
            ACTION="$arg"
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

# Execute action
case "$ACTION" in
    create)
        action_create
        ;;
    show)
        action_show
        ;;
    update)
        action_update
        ;;
    check)
        action_check
        ;;
    *)
        echo "Usage: $0 {create|show|update|check} [options]" >&2
        echo "  create  - Create new constitution (interactive)" >&2
        echo "  show    - Show constitution content" >&2
        echo "  update  - Update constitution (interactive)" >&2
        echo "  check   - Check content compliance" >&2
        exit 1
        ;;
esac

