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

CHARACTERS_DIR="$REPO_ROOT/world/characters"
STATE_FILE="$REPO_ROOT/.novelkit/memory/config.json"
TEMPLATE_FILE="$REPO_ROOT/.novelkit/templates/character.md"

# Ensure directories exist
mkdir -p "$CHARACTERS_DIR"

# Check config.json exists
if [ ! -f "$STATE_FILE" ]; then
    echo "Error: config.json not found in .novelkit/memory/. It should already exist." >&2
    exit 1
fi

# Get next character ID
get_next_character_id() {
    local highest=0
    if [ -d "$CHARACTERS_DIR" ]; then
        for file in "$CHARACTERS_DIR"/character-*.md; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")
            number=$(echo "$filename" | grep -o '[0-9]\+' | head -1 || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    printf "character-%03d" $((highest + 1))
}

# Parse JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "new")
            local char_id="$1"
            local char_name="$2"
            local char_file="$3"
            cat <<EOF
{
  "action": "new",
  "success": true,
  "character_id": "$char_id",
  "character_name": "$char_name",
  "character_file": "$char_file",
  "characters_dir": "$CHARACTERS_DIR"
}
EOF
            ;;
        "list")
            local json_chars="$1"
            cat <<EOF
{
  "action": "list",
  "success": true,
  "characters": $json_chars
}
EOF
            ;;
        "show")
            local char_id="$1"
            local char_file="$2"
            cat <<EOF
{
  "action": "show",
  "success": true,
  "character_id": "$char_id",
  "character_file": "$char_file"
}
EOF
            ;;
        "update")
            local char_id="$1"
            local char_file="$2"
            cat <<EOF
{
  "action": "update",
  "success": true,
  "character_id": "$char_id",
  "character_file": "$char_file"
}
EOF
            ;;
        "delete")
            local char_id="$1"
            cat <<EOF
{
  "action": "delete",
  "success": true,
  "character_id": "$char_id"
}
EOF
            ;;
        "search")
            local json_results="$1"
            cat <<EOF
{
  "action": "search",
  "success": true,
  "results": $json_results
}
EOF
            ;;
    esac
}

# Find character by ID or name
find_character() {
    local search="$1"
    if [ -z "$search" ]; then
        return 1
    fi
    
    # Try exact ID match first
    if [ -f "$CHARACTERS_DIR/$search.md" ]; then
        echo "$search"
        return
    fi
    
    if [ -f "$CHARACTERS_DIR/character-$search.md" ]; then
        echo "character-$search"
        return
    fi
    
    # Try name matching
    for file in "$CHARACTERS_DIR"/character-*.md; do
        [ -f "$file" ] || continue
        if [ -f "$file" ]; then
            # Extract name from the first H1 header
            name=$(grep -E "^# 角色档案：" "$file" | sed 's/# 角色档案：//' | head -1 | xargs)
            if [ -z "$name" ]; then
                 # Fallback to English header
                 name=$(grep -E "^# Character Profile:" "$file" | sed 's/# Character Profile: //' | head -1 | xargs)
            fi
            
            # Also check the name field
            name_field=$(grep -E "^\- \*\*姓名\*\*：" "$file" | sed 's/\- \*\*姓名\*\*：//' | head -1 | xargs)
            
            if echo "$name" | grep -qi "$search" || echo "$name_field" | grep -qi "$search"; then
                basename "$file" .md
                return
            fi
        fi
    done
    
    return 1
}

# Action handlers
action_new() {
    local args="$*"
    local char_name=""
    local char_id=""
    
    # Extract character name if provided
    if [ -n "$args" ]; then
        char_name="$args"
    fi
    
    # Generate ID
    char_id=$(get_next_character_id)
    
    # Create character file from template
    char_file="$CHARACTERS_DIR/$char_id.md"
    
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$char_file"
        # Replace placeholders
        current_date=$(date +"%Y-%m-%d")
        sed -i "s/\[CHARACTER_NAME\]/$char_name/g" "$char_file"
        sed -i "s/\[NAME\]/$char_name/g" "$char_file"
        sed -i "s/\[DATE\]/$current_date/g" "$char_file"
        sed -i "s/\[CHARACTER_ID\]/$char_id/g" "$char_file"
        sed -i "s/\[STATUS\]/Active/g" "$char_file"
    else
        # Create minimal template if template doesn't exist
        cat > "$char_file" <<EOF
# 角色档案：$char_name

**创建时间**：$(date +"%Y-%m-%d")
**最后更新**：$(date +"%Y-%m-%d")
**ID**：$char_id
**状态**：Active

## 1. 基本信息 (Basic Information)

- **姓名**：$char_name
- **别名/称号**：
- **性别**：
- **年龄**：
- **种族**：
- **身份/职业**：
- **所属阵营**：
- **出生地**：
- **现居地**：

[Content to be filled by AI]
EOF
    fi
    
    json_output "new" "$char_id" "$char_name" "$char_file"
}

action_list() {
    local chars_json="[]"
    
    if [ -d "$CHARACTERS_DIR" ]; then
        local chars_array="["
        local first=true
        
        for file in "$CHARACTERS_DIR"/character-*.md; do
            [ -f "$file" ] || continue
            char_id=$(basename "$file" .md)
            
            # Extract info
            name=$(grep -E "^# 角色档案：" "$file" | sed 's/# 角色档案：//' | head -1 | xargs)
            if [ -z "$name" ]; then name="$char_id"; fi
            
            role=$(grep -E "^\- \*\*角色定位\*\*：" "$file" | sed 's/\- \*\*角色定位\*\*：//' | head -1 | xargs || echo "未定义")
            status=$(grep -E "^\*\*状态\*\*：" "$file" | sed 's/\*\*状态\*\*：//' | head -1 | xargs || echo "Active")
            updated=$(grep -E "^\*\*最后更新\*\*：" "$file" | sed 's/\*\*最后更新\*\*：//' | head -1 | xargs || echo "")
            
            if [ "$first" = true ]; then
                first=false
            else
                chars_array="$chars_array,"
            fi
            
            chars_array="$chars_array{"id":"$char_id","name":"$name","role":"$role","status":"$status","updated":"$updated"}"
        done
        
        chars_array="$chars_array]"
        chars_json="$chars_array"
    fi
    
    json_output "list" "$chars_json"
}

action_show() {
    local search="$*"
    local char_id=$(find_character "$search")
    
    if [ -z "$char_id" ]; then
        echo "{"action":"show","success":false,"error":"Character not found: $search"}" >&2
        exit 1
    fi
    
    char_file="$CHARACTERS_DIR/$char_id.md"
    if [ ! -f "$char_file" ]; then
        echo "{"action":"show","success":false,"error":"Character file not found: $char_file"}" >&2
        exit 1
    fi
    
    json_output "show" "$char_id" "$char_file"
}

action_update() {
    local args="$*"
    local char_id=""
    local updates=""
    
    # Parse: char_id/name ...
    first_word=$(echo "$args" | cut -d' ' -f1)
    
    # Try to find character
    char_id=$(find_character "$first_word")
    
    if [ -z "$char_id" ]; then
        echo "{"action":"update","success":false,"error":"Character not found: $first_word"}" >&2
        exit 1
    fi
    
    char_file="$CHARACTERS_DIR/$char_id.md"
    if [ ! -f "$char_file" ]; then
        echo "{"action":"update","success":false,"error":"Character file not found: $char_file"}" >&2
        exit 1
    fi
    
    # Update will be handled by AI, just return file path
    json_output "update" "$char_id" "$char_file"
}

action_delete() {
    local search="$*"
    local char_id=$(find_character "$search")
    
    if [ -z "$char_id" ]; then
        echo "{"action":"delete","success":false,"error":"Character not found: $search"}" >&2
        exit 1
    fi
    
    char_file="$CHARACTERS_DIR/$char_id.md"
    if [ ! -f "$char_file" ]; then
        echo "{"action":"delete","success":false,"error":"Character file not found: $char_file"}" >&2
        exit 1
    fi
    
    # Create backup before delete (or move to trash)
    trash_dir="$REPO_ROOT/.novelkit/trash"
    mkdir -p "$trash_dir"
    mv "$char_file" "$trash_dir/"
    
    json_output "delete" "$char_id"
}

# Main script
ACTION=""
ARGS=()

# Parse arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        new|list|show|update|delete|search)
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
    delete)
        action_delete "${ARGS[@]}"
        ;;
    *)
        echo "Usage: $0 {new|list|show|update|delete} [arguments]" >&2
        exit 1
        ;;
esac
