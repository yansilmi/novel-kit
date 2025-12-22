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

WRITERS_DIR="$REPO_ROOT/.novelkit/writers"
STATE_FILE="$REPO_ROOT/.novelkit/memory/config.json"
TEMPLATE_FILE="$REPO_ROOT/.novelkit/templates/writer.md"

# Ensure directories exist
mkdir -p "$WRITERS_DIR"

# Check config.json exists (should already exist, don't create it)
if [ ! -f "$STATE_FILE" ]; then
    echo "Error: config.json not found in .novelkit/memory/. It should already exist." >&2
    exit 1
fi

# Get next writer ID
get_next_writer_id() {
    local highest=0
    if [ -d "$WRITERS_DIR" ]; then
        for dir in "$WRITERS_DIR"/writer-*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            number=$(echo "$dirname" | grep -o '[0-9]\+$' || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    printf "writer-%03d" $((highest + 1))
}

# Parse JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "new")
            local writer_id="$1"
            local writer_name="$2"
            local writer_file="$3"
            cat <<EOF
{
  "action": "new",
  "success": true,
  "writer_id": "$writer_id",
  "writer_name": "$writer_name",
  "writer_file": "$writer_file",
  "writers_dir": "$WRITERS_DIR"
}
EOF
            ;;
        "list")
            local json_writers="$1"
            cat <<EOF
{
  "action": "list",
  "success": true,
  "writers": $json_writers,
  "current_writer": "$(get_current_writer)"
}
EOF
            ;;
        "show")
            local writer_id="$1"
            local writer_file="$2"
            cat <<EOF
{
  "action": "show",
  "success": true,
  "writer_id": "$writer_id",
  "writer_file": "$writer_file"
}
EOF
            ;;
        "update")
            local writer_id="$1"
            local writer_file="$2"
            cat <<EOF
{
  "action": "update",
  "success": true,
  "writer_id": "$writer_id",
  "writer_file": "$writer_file"
}
EOF
            ;;
        "switch")
            local writer_id="$1"
            cat <<EOF
{
  "action": "switch",
  "success": true,
  "writer_id": "$writer_id",
  "current_writer": "$writer_id"
}
EOF
            ;;
    esac
}

# Get current writer from state file
get_current_writer() {
    if [ -f "$STATE_FILE" ]; then
        python3 -c "import json, sys; data = json.load(open('$STATE_FILE')); print(data.get('current_writer', {}).get('id', '') or '')" 2>/dev/null || echo ""
    fi
}

# Set current writer in state file (note: AI will update this, not script)
set_current_writer() {
    local writer_id="$1"
    # This function is kept for backward compatibility
    # Actual state update is done by AI in writer-switch command
    echo "Note: State update should be done by AI, not script" >&2
}

# Find writer by ID or name
find_writer() {
    local search="$1"
    if [ -z "$search" ]; then
        get_current_writer
        return
    fi
    
    # Try exact ID match first
    if [ -d "$WRITERS_DIR/$search" ]; then
        echo "$search"
        return
    fi
    
    # Try name matching
    for dir in "$WRITERS_DIR"/writer-*; do
        [ -d "$dir" ] || continue
        writer_file="$dir/writer.md"
        if [ -f "$writer_file" ]; then
            name=$(grep -E "^# Writer Profile:" "$writer_file" | sed 's/# Writer Profile: //' | head -1 | xargs)
            if echo "$name" | grep -qi "$search"; then
                basename "$dir"
                return
            fi
        fi
    done
    
    return 1
}

# Action handlers
action_new() {
    local description="$*"
    local writer_name=""
    local writer_id=""
    
    # Extract writer name from description (first few words)
    if [ -n "$description" ]; then
        writer_name=$(echo "$description" | cut -d' ' -f1-3 | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        # Clean up the name
        writer_name=$(echo "$writer_name" | sed 's/[^a-z0-9-]//g')
    fi
    
    # Generate ID
    writer_id=$(get_next_writer_id)
    
    # Create writer directory
    writer_dir="$WRITERS_DIR/$writer_id"
    mkdir -p "$writer_dir"
    
    # Create writer profile from template
    writer_file="$writer_dir/writer.md"
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$writer_file"
        # Replace placeholders
        current_date=$(date +"%Y-%m-%d")
        sed -i.bak "s/\[WRITER_NAME\]/$writer_name/g" "$writer_file"
        sed -i.bak "s/\[DATE\]/$current_date/g" "$writer_file"
        sed -i.bak "s/\[WRITER_ID\]/$writer_id/g" "$writer_file"
        rm -f "$writer_file.bak"
    else
        # Create minimal template if template doesn't exist
        cat > "$writer_file" <<EOF
# Writer Profile: $writer_name

**Created**: $current_date
**Last Updated**: $current_date
**Status**: Active
**Current Writer**: No
**ID**: $writer_id

## Basic Information

- **Name**: $writer_name
- **ID**: $writer_id
- **Description**: $description

## Writing Style Characteristics

[To be filled by AI]

EOF
    fi
    
    json_output "new" "$writer_id" "$writer_name" "$writer_file"
}

action_list() {
    local writers_json="[]"
    
    if [ -d "$WRITERS_DIR" ]; then
        local current=$(get_current_writer)
        local writers_array="["
        local first=true
        
        for dir in "$WRITERS_DIR"/writer-*; do
            [ -d "$dir" ] || continue
            writer_id=$(basename "$dir")
            writer_file="$dir/writer.md"
            
            if [ -f "$writer_file" ]; then
                name=$(grep -E "^# Writer Profile:" "$writer_file" | sed 's/# Writer Profile: //' | head -1 | xargs || echo "$writer_id")
                status=$(grep -E "^\*\*Status\*\*:" "$writer_file" | sed 's/\*\*Status\*\*: //' | head -1 | xargs || echo "Active")
                updated=$(grep -E "^\*\*Last Updated\*\*:" "$writer_file" | sed 's/\*\*Last Updated\*\*: //' | head -1 | xargs || echo "")
                desc=$(grep -E "^\*\*Description\*\*:" "$writer_file" | sed 's/\*\*Description\*\*: //' | head -1 | xargs || echo "")
                is_current="false"
                [ "$writer_id" = "$current" ] && is_current="true"
                
                if [ "$first" = true ]; then
                    first=false
                else
                    writers_array="$writers_array,"
                fi
                
                writers_array="$writers_array{\"id\":\"$writer_id\",\"name\":\"$name\",\"status\":\"$status\",\"updated\":\"$updated\",\"description\":\"$desc\",\"current\":$is_current}"
            fi
        done
        
        writers_array="$writers_array]"
        writers_json="$writers_array"
    fi
    
    json_output "list" "$writers_json"
}

action_show() {
    local search="$*"
    local writer_id=$(find_writer "$search")
    
    if [ -z "$writer_id" ]; then
        echo "{\"action\":\"show\",\"success\":false,\"error\":\"Writer not found: $search\"}" >&2
        exit 1
    fi
    
    writer_file="$WRITERS_DIR/$writer_id/writer.md"
    if [ ! -f "$writer_file" ]; then
        echo "{\"action\":\"show\",\"success\":false,\"error\":\"Writer file not found: $writer_file\"}" >&2
        exit 1
    fi
    
    json_output "show" "$writer_id" "$writer_file"
}

action_update() {
    local args="$*"
    local writer_id=""
    local updates=""
    
    # Parse: writer_id field1:value1 field2:value2
    first_word=$(echo "$args" | cut -d' ' -f1)
    rest=$(echo "$args" | cut -d' ' -f2-)
    
    # Try to find writer
    writer_id=$(find_writer "$first_word")
    if [ -z "$writer_id" ]; then
        # Maybe first word is part of update, use current writer
        writer_id=$(get_current_writer)
        updates="$args"
    else
        updates="$rest"
    fi
    
    if [ -z "$writer_id" ]; then
        echo "{\"action\":\"update\",\"success\":false,\"error\":\"No writer specified and no current writer\"}" >&2
        exit 1
    fi
    
    writer_file="$WRITERS_DIR/$writer_id/writer.md"
    if [ ! -f "$writer_file" ]; then
        echo "{\"action\":\"update\",\"success\":false,\"error\":\"Writer file not found: $writer_file\"}" >&2
        exit 1
    fi
    
    # Update will be handled by AI, just return file path
    json_output "update" "$writer_id" "$writer_file"
}

action_switch() {
    local search="$*"
    local writer_id=$(find_writer "$search")
    
    if [ -z "$writer_id" ]; then
        echo "{\"action\":\"switch\",\"success\":false,\"error\":\"Writer not found: $search\"}" >&2
        exit 1
    fi
    
    set_current_writer "$writer_id"
    json_output "switch" "$writer_id"
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
        new|list|show|update|switch)
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
    new)
        action_new "${ARGS[@]}"
        ;;
    list)
        action_list
        ;;
    show)
        action_show "${ARGS[@]}"
        ;;
    update)
        action_update "${ARGS[@]}"
        ;;
    switch)
        action_switch "${ARGS[@]}"
        ;;
    *)
        echo "Usage: $0 {new|list|show|update|switch} [options] [arguments]" >&2
        echo "  new <description>     - Create a new writer" >&2
        echo "  list                  - List all writers" >&2
        echo "  show [writer_id]      - Show writer details" >&2
        echo "  update <id> <updates> - Update writer profile" >&2
        echo "  switch <writer_id>    - Switch active writer" >&2
        exit 1
        ;;
esac

