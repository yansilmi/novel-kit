#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

CONFIG_FILE="$REPO_ROOT/.novelkit/memory/config.json"
NOVEL_TITLE=""
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --novel-title)
            NOVEL_TITLE="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --json)
            # JSON output mode
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    if [ ! -d "$REPO_ROOT/.novelkit" ]; then
        echo "{\"success\": false, \"error\": \"Meta-space (.novelkit/) not found. Please install NovelKit properly.\"}" >&2
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"success\": false, \"error\": \"config.json not found in .novelkit/memory/. It should already exist.\"}" >&2
        exit 1
    fi
    
    if [ ! -d "$REPO_ROOT/.novelkit/scripts" ]; then
        echo "{\"success\": false, \"error\": \"Scripts directory not found in meta-space.\"}" >&2
        exit 1
    fi
    
    if [ ! -d "$REPO_ROOT/.novelkit/templates" ]; then
        echo "{\"success\": false, \"error\": \"Templates directory not found in meta-space.\"}" >&2
        exit 1
    fi
}

# Check if already initialized
check_initialized() {
    local dirs_exist=false
    
    if [ -d "$REPO_ROOT/chapters" ] || \
       [ -d "$REPO_ROOT/world" ] || \
       [ -d "$REPO_ROOT/plots" ]; then
        dirs_exist=true
    fi
    
    if [ "$dirs_exist" = true ] && [ "$FORCE" = false ]; then
        echo "{\"success\": false, \"error\": \"User space directories already exist. Use --force to re-initialize.\", \"already_initialized\": true}" >&2
        exit 1
    fi
}

# Create user space directories
create_directories() {
    mkdir -p "$REPO_ROOT/chapters"
    mkdir -p "$REPO_ROOT/world/characters"
    mkdir -p "$REPO_ROOT/world/items"
    mkdir -p "$REPO_ROOT/world/locations"
    mkdir -p "$REPO_ROOT/world/factions"
    mkdir -p "$REPO_ROOT/world/rules"
    mkdir -p "$REPO_ROOT/world/relationships"
    mkdir -p "$REPO_ROOT/plots/main"
    mkdir -p "$REPO_ROOT/plots/side"
    mkdir -p "$REPO_ROOT/plots/foreshadowing"
}

# Create novel.md if not exists
create_novel_file() {
    local novel_file="$REPO_ROOT/novel.md"
    
    if [ ! -f "$novel_file" ]; then
        cat > "$novel_file" <<EOF
# ${NOVEL_TITLE:-[Novel Title]}

**Status**: Draft  
**Created**: $(date +"%Y-%m-%d")  
**Total Chapters**: 0  
**Total Words**: 0

## Synopsis

[Novel synopsis will be added here]

## Table of Contents

- Chapter 1: [Title] (Coming soon)

## Statistics

- **Total Chapters**: 0
- **Total Words**: 0
- **Average Words per Chapter**: 0

---

*This novel is being written with NovelKit.*
EOF
        echo "$novel_file"
    fi
}

# Update .gitignore if .git exists
update_gitignore() {
    if [ -d "$REPO_ROOT/.git" ]; then
        local gitignore="$REPO_ROOT/.gitignore"
        local needs_update=false
        
        if [ ! -f "$gitignore" ]; then
            touch "$gitignore"
            needs_update=true
        fi
        
        if ! grep -q "^\.novelkit/" "$gitignore" 2>/dev/null; then
            echo "" >> "$gitignore"
            echo "# NovelKit meta-space (always ignore)" >> "$gitignore"
            echo ".novelkit/" >> "$gitignore"
            echo ".cursor/" >> "$gitignore"
            needs_update=true
        fi
        
        if [ "$needs_update" = true ]; then
            echo "$gitignore"
        fi
    fi
}

# Update config.json
update_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"success\": false, \"error\": \"config.json not found. It should already exist.\"}" >&2
        exit 1
    fi
    
    # Use Python or jq if available, otherwise use sed (basic update)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Try jq first
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg title "$NOVEL_TITLE" \
           --arg ts "$timestamp" \
           '.novel.created_at = (if .novel.created_at == null then $ts else .novel.created_at end) |
            .novel.title = (if $title != "" then $title else .novel.title end) |
            .novel.last_modified = $ts |
            .session.last_action = "Project initialized" |
            .session.last_action_time = $ts |
            .session.last_action_command = "novel-setup" |
            .session.last_modified_file = null |
            .last_updated = $ts' \
           "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
    else
        # Fallback: basic sed update (limited)
        echo "Warning: jq not found, using basic update. Install jq for better JSON handling." >&2
        # For now, just update last_updated
        sed -i.bak "s/\"last_updated\": \".*\"/\"last_updated\": \"$timestamp\"/" "$CONFIG_FILE"
        rm -f "${CONFIG_FILE}.bak"
    fi
}

# Main execution
main() {
    check_prerequisites
    check_initialized
    create_directories
    
    local novel_file=$(create_novel_file)
    local gitignore=$(update_gitignore)
    
    update_config
    
    # Output JSON result
    local dirs_json=$(cat <<EOF
[
  "chapters",
  "world/characters",
  "world/items",
  "world/locations",
  "world/factions",
  "world/rules",
  "world/relationships",
  "plots/main",
  "plots/side",
  "plots/foreshadowing"
]
EOF
)
    
    local files_json="[]"
    if [ -n "$novel_file" ]; then
        files_json="[\"novel.md\"]"
    fi
    
    cat <<EOF
{
  "success": true,
  "message": "NovelKit project initialized successfully",
  "directories_created": $dirs_json,
  "files_created": $files_json,
  "config_updated": true,
  "novel_title": ${NOVEL_TITLE:+"\"$NOVEL_TITLE\""}${NOVEL_TITLE:-null}
}
EOF
}

main

