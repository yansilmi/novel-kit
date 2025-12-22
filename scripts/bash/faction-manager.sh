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

FACTIONS_DIR="$REPO_ROOT/world/factions"
STATE_FILE="$REPO_ROOT/.novelkit/memory/config.json"
TEMPLATE_FILE="$REPO_ROOT/.novelkit/templates/faction.md"

# Ensure directories exist
mkdir -p "$FACTIONS_DIR"

# Check config.json exists
if [ ! -f "$STATE_FILE" ]; then
    echo "Error: config.json not found in .novelkit/memory/. It should already exist." >&2
    exit 1
fi

# Get next faction ID
get_next_faction_id() {
    local highest=0
    if [ -d "$FACTIONS_DIR" ]; then
        for file in "$FACTIONS_DIR"/faction-*.md; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")
            number=$(echo "$filename" | grep -o '[0-9]\+' | head -1 || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    printf "faction-%03d" $((highest + 1))
}

# Parse JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "new")
            local id="$1"
            local name="$2"
            local file="$3"
            cat <<EOF
{
  "action": "new",
  "success": true,
  "faction_id": "$id",
  "faction_name": "$name",
  "faction_file": "$file",
  "factions_dir": "$FACTIONS_DIR"
}
EOF
            ;;
        "list")
            local json_list="$1"
            cat <<EOF
{
  "action": "list",
  "success": true,
  "factions": $json_list
}
EOF
            ;;
        "show")
            local id="$1"
            local file="$2"
            cat <<EOF
{
  "action": "show",
  "success": true,
  "faction_id": "$id",
  "faction_file": "$file"
}
EOF
            ;;
        "update")
            local id="$1"
            local file="$2"
            cat <<EOF
{
  "action": "update",
  "success": true,
  "faction_id": "$id",
  "faction_file": "$file"
}
EOF
            ;;
        "delete")
            local id="$1"
            cat <<EOF
{
  "action": "delete",
  "success": true,
  "faction_id": "$id"
}
EOF
            ;;
    esac
}

# Find faction by ID or name
find_faction() {
    local search="$1"
    if [ -z "$search" ]; then
        return 1
    fi
    
    # Try exact ID match first
    if [ -f "$FACTIONS_DIR/$search.md" ]; then
        echo "$search"
        return
    fi
    
    if [ -f "$FACTIONS_DIR/faction-$search.md" ]; then
        echo "faction-$search"
        return
    fi
    
    # Try name matching
    for file in "$FACTIONS_DIR"/faction-*.md; do
        [ -f "$file" ] || continue
        if [ -f "$file" ]; then
            # Extract name from the first H1 header
            name=$(grep -E "^# 阵营档案：" "$file" | sed 's/# 阵营档案：//' | head -1 | xargs)
            if [ -z "$name" ]; then
                 name=$(grep -E "^# Faction Profile:" "$file" | sed 's/# Faction Profile: //' | head -1 | xargs)
            fi
            
            # Also check the name field
            name_field=$(grep -E "^\- \*\*名称\*\*：" "$file" | sed 's/\- \*\*名称\*\*：//' | head -1 | xargs)
            
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
    local name=""
    local id=""
    
    # Extract name if provided
    if [ -n "$args" ]; then
        name="$args"
    fi
    
    # Generate ID
    id=$(get_next_faction_id)
    
    # Create file from template
    file="$FACTIONS_DIR/$id.md"
    
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$file"
        # Replace placeholders
        current_date=$(date +"%Y-%m-%d")
        sed -i "s/\[FACTION_NAME\]/$name/g" "$file"
        sed -i "s/\[NAME\]/$name/g" "$file"
        sed -i "s/\[DATE\]/$current_date/g" "$file"
        sed -i "s/\[FACTION_ID\]/$id/g" "$file"
        sed -i "s/\[STATUS\]/Active/g" "$file"
    else
        # Fallback minimal template
        cat > "$file" <<EOF
# 阵营档案：$name

**创建时间**：$(date +"%Y-%m-%d")
**最后更新**：$(date +"%Y-%m-%d")
**ID**：$id
**状态**：Active

## 1. 基本信息 (Basic Information)

- **名称**：$name
- **别名**：
- **类型**：
- **规模**：

[Content to be filled by AI]
EOF
    fi
    
    json_output "new" "$id" "$name" "$file"
}

action_list() {
    local json="[]"
    
    if [ -d "$FACTIONS_DIR" ]; then
        local array="["
        local first=true
        
        for file in "$FACTIONS_DIR"/faction-*.md; do
            [ -f "$file" ] || continue
            id=$(basename "$file" .md)
            
            # Extract info
            name=$(grep -E "^# 阵营档案：" "$file" | sed 's/# 阵营档案：//' | head -1 | xargs)
            if [ -z "$name" ]; then name="$id"; fi
            
            type=$(grep -E "^\- \*\*类型\*\*：" "$file" | sed 's/\- \*\*类型\*\*：//' | head -1 | xargs || echo "未定义")
            status=$(grep -E "^\*\*状态\*\*：" "$file" | sed 's/\*\*状态\*\*：//' | head -1 | xargs || echo "Active")
            updated=$(grep -E "^\*\*最后更新\*\*：" "$file" | sed 's/\*\*最后更新\*\*：//' | head -1 | xargs || echo "")
            
            if [ "$first" = true ]; then
                first=false
            else
                array="$array,"
            fi
            
            array="$array{"id":"$id","name":"$name","type":"$type","status":"$status","updated":"$updated"}"
        done
        
        array="$array]"
        json="$array"
    fi
    
    json_output "list" "$json"
}

action_show() {
    local search="$*"
    local id=$(find_faction "$search")
    
    if [ -z "$id" ]; then
        echo "{"action":"show","success":false,"error":"Faction not found: $search"}" >&2
        exit 1
    fi
    
    file="$FACTIONS_DIR/$id.md"
    if [ ! -f "$file" ]; then
        echo "{"action":"show","success":false,"error":"File not found: $file"}" >&2
        exit 1
    fi
    
    json_output "show" "$id" "$file"
}

action_update() {
    local args="$*"
    local id=""
    
    first_word=$(echo "$args" | cut -d' ' -f1)
    id=$(find_faction "$first_word")
    
    if [ -z "$id" ]; then
        echo "{"action":"update","success":false,"error":"Faction not found: $first_word"}" >&2
        exit 1
    fi
    
    file="$FACTIONS_DIR/$id.md"
    if [ ! -f "$file" ]; then
        echo "{"action":"update","success":false,"error":"File not found: $file"}" >&2
        exit 1
    fi
    
    json_output "update" "$id" "$file"
}

action_delete() {
    local search="$*"
    local id=$(find_faction "$search")
    
    if [ -z "$id" ]; then
        echo "{"action":"delete","success":false,"error":"Faction not found: $search"}" >&2
        exit 1
    fi
    
    file="$FACTIONS_DIR/$id.md"
    if [ ! -f "$file" ]; then
        echo "{"action":"delete","success":false,"error":"File not found: $file"}" >&2
        exit 1
    fi
    
    # Move to trash
    trash_dir="$REPO_ROOT/.novelkit/trash"
    mkdir -p "$trash_dir"
    mv "$file" "$trash_dir/"
    
    json_output "delete" "$id"
}

# Main script
ACTION=""
ARGS=()

# Parse arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        new|list|show|update|delete)
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
