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

PLOTS_DIR="$REPO_ROOT/plots"
MAIN_PLOTS_DIR="$PLOTS_DIR/main"
SIDE_PLOTS_DIR="$PLOTS_DIR/side"
FORESHADOW_DIR="$PLOTS_DIR/foreshadowing"
STATE_FILE="$REPO_ROOT/.novelkit/memory/config.json"
TEMPLATE_FILE="$REPO_ROOT/.novelkit/templates/plot.md"

# Ensure directories exist
mkdir -p "$MAIN_PLOTS_DIR" "$SIDE_PLOTS_DIR" "$FORESHADOW_DIR"

# Check config.json exists
if [ ! -f "$STATE_FILE" ]; then
    echo "Error: config.json not found in .novelkit/memory/. It should already exist." >&2
    exit 1
fi

# Get next plot ID
get_next_plot_id() {
    local type="$1"
    local dir=""
    local prefix=""
    
    case "$type" in
        "main") 
            dir="$MAIN_PLOTS_DIR"
            prefix="main-plot"
            ;;
        "side") 
            dir="$SIDE_PLOTS_DIR"
            prefix="side-plot"
            ;;
        "foreshadow") 
            dir="$FORESHADOW_DIR"
            prefix="foreshadow"
            ;;
        *) 
            echo "Error: Unknown plot type" >&2
            exit 1
            ;;
    esac
    
    local highest=0
    if [ -d "$dir" ]; then
        for file in "$dir"/"$prefix"-*.md; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")
            number=$(echo "$filename" | grep -o '[0-9]\+' | head -1 || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    printf "%s-%03d" "$prefix" $((highest + 1))
}

# Parse JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "new")
            local id="$1"
            local title="$2"
            local file="$3"
            local type="$4"
            cat <<EOF
{
  "action": "new",
  "success": true,
  "plot_id": "$id",
  "plot_title": "$title",
  "plot_type": "$type",
  "plot_file": "$file"
}
EOF
            ;;
        "list")
            local json_list="$1"
            cat <<EOF
{
  "action": "list",
  "success": true,
  "plots": $json_list
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
  "plot_id": "$id",
  "plot_file": "$file"
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
  "plot_id": "$id",
  "plot_file": "$file"
}
EOF
            ;;
        "delete")
            local id="$1"
            cat <<EOF
{
  "action": "delete",
  "success": true,
  "plot_id": "$id"
}
EOF
            ;;
    esac
}

# Find plot by ID or Title
find_plot() {
    local search="$1"
    if [ -z "$search" ]; then
        return 1
    fi
    
    # Try exact ID match first
    if [ -f "$MAIN_PLOTS_DIR/$search.md" ]; then echo "$MAIN_PLOTS_DIR/$search.md"; return; fi
    if [ -f "$SIDE_PLOTS_DIR/$search.md" ]; then echo "$SIDE_PLOTS_DIR/$search.md"; return; fi
    if [ -f "$FORESHADOW_DIR/$search.md" ]; then echo "$FORESHADOW_DIR/$search.md"; return; fi
    
    # Try with type prefix
    if [ -f "$MAIN_PLOTS_DIR/main-plot-$search.md" ]; then echo "$MAIN_PLOTS_DIR/main-plot-$search.md"; return; fi
    if [ -f "$SIDE_PLOTS_DIR/side-plot-$search.md" ]; then echo "$SIDE_PLOTS_DIR/side-plot-$search.md"; return; fi
    if [ -f "$FORESHADOW_DIR/foreshadow-$search.md" ]; then echo "$FORESHADOW_DIR/foreshadow-$search.md"; return; fi
    
    # Search by Title in all directories
    for dir in "$MAIN_PLOTS_DIR" "$SIDE_PLOTS_DIR" "$FORESHADOW_DIR"; do
        for file in "$dir"/*.md; do
            [ -f "$file" ] || continue
            title=$(grep -E "^# 剧情档案：" "$file" | sed 's/# 剧情档案：//' | head -1 | xargs)
            
            # Check Title field
            title_field=$(grep -E "^\- \*\*标题\*\*：" "$file" | sed 's/\- \*\*标题\*\*：//' | head -1 | xargs)
            
            if echo "$title" | grep -qi "$search" || echo "$title_field" | grep -qi "$search"; then
                echo "$file"
                return
            fi
        done
    done
    
    return 1
}

# Action handlers
action_new() {
    local type="$1"
    local title="${*:2}"
    local id=$(get_next_plot_id "$type")
    local dir=""
    local type_display=""
    
    case "$type" in
        "main") 
            dir="$MAIN_PLOTS_DIR"
            type_display="Main"
            ;;
        "side") 
            dir="$SIDE_PLOTS_DIR"
            type_display="Side"
            ;;
        "foreshadow") 
            dir="$FORESHADOW_DIR"
            type_display="Foreshadow"
            ;;
    esac
    
    local file="$dir/$id.md"
    
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$file"
        current_date=$(date +"%Y-%m-%d")
        sed -i "s/\[PLOT_NAME\]/$title/g" "$file"
        sed -i "s/\[TITLE\]/$title/g" "$file"
        sed -i "s/\[DATE\]/$current_date/g" "$file"
        sed -i "s/\[PLOT_ID\]/$id/g" "$file"
        sed -i "s/\[PLOT_TYPE\]/$type_display/g" "$file"
        sed -i "s/\[STATUS\]/Planned/g" "$file"
    else
        cat > "$file" <<EOF
# 剧情档案：$title

**创建时间**：$(date +"%Y-%m-%d")
**最后更新**：$(date +"%Y-%m-%d")
**ID**：$id
**类型**：$type_display
**状态**：Planned

## 1. 核心概要 (Core Summary)

- **标题**：$title

[Content to be filled by AI]
EOF
    fi
    
    json_output "new" "$id" "$title" "$file" "$type"
}

action_list() {
    local type="$1" # Optional: main, side, foreshadow
    local json="[]"
    local array="["
    local first=true
    
    dirs=()
    if [ -z "$type" ] || [ "$type" == "all" ]; then
        dirs=("$MAIN_PLOTS_DIR" "$SIDE_PLOTS_DIR" "$FORESHADOW_DIR")
    elif [ "$type" == "main" ]; then
        dirs=("$MAIN_PLOTS_DIR")
    elif [ "$type" == "side" ]; then
        dirs=("$SIDE_PLOTS_DIR")
    elif [ "$type" == "foreshadow" ]; then
        dirs=("$FORESHADOW_DIR")
    fi
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            for file in "$dir"/*.md; do
                [ -f "$file" ] || continue
                id=$(basename "$file" .md)
                
                title=$(grep -E "^# 剧情档案：" "$file" | sed 's/# 剧情档案：//' | head -1 | xargs)
                if [ -z "$title" ]; then title="$id"; fi
                
                status=$(grep -E "^\*\*状态\*\*：" "$file" | sed 's/\*\*状态\*\*：//' | head -1 | xargs || echo "Unknown")
                type_val=$(grep -E "^\*\*类型\*\*：" "$file" | sed 's/\*\*类型\*\*：//' | head -1 | xargs || echo "Unknown")
                updated=$(grep -E "^\*\*最后更新\*\*：" "$file" | sed 's/\*\*最后更新\*\*：//' | head -1 | xargs || echo "")
                
                if [ "$first" = true ]; then
                    first=false
                else
                    array="$array,"
                fi
                
                array="$array{"id":"$id","title":"$title","type":"$type_val","status":"$status","updated":"$updated"}"
            done
        fi
    done
    
    array="$array]"
    json="$array"
    
    json_output "list" "$json"
}

action_show() {
    local search="$*"
    local file=$(find_plot "$search")
    
    if [ -z "$file" ]; then
        echo "{"action":"show","success":false,"error":"Plot not found: $search"}" >&2
        exit 1
    fi
    
    id=$(basename "$file" .md)
    json_output "show" "$id" "$file"
}

action_update() {
    local args="$*"
    first_word=$(echo "$args" | cut -d' ' -f1)
    file=$(find_plot "$first_word")
    
    if [ -z "$file" ]; then
        echo "{"action":"update","success":false,"error":"Plot not found: $first_word"}" >&2
        exit 1
    fi
    
    id=$(basename "$file" .md)
    json_output "update" "$id" "$file"
}

# Main script
ACTION=""
TYPE=""
ARGS=()

# Parse arguments
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        new)
            ACTION="new"
            ;;
        list)
            ACTION="list"
            ;;
        show)
            ACTION="show"
            ;;
        update)
            ACTION="update"
            ;;
        --type)
            i=$((i + 1))
            TYPE="${!i}"
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
        # require type for new
        if [ -z "$TYPE" ]; then
             # Default or Error? Let's error to be safe, or command wrapper handles it
             echo "Error: --type required for new (main/side/foreshadow)" >&2
             exit 1
        fi
        action_new "$TYPE" "${ARGS[@]}"
        ;;
    list)
        action_list "$TYPE"
        ;;
    show)
        action_show "${ARGS[@]}"
        ;;
    update)
        action_update "${ARGS[@]}"
        ;;
    *)
        echo "Usage: $0 {new --type <main|side|foreshadow>|list|show|update} [arguments]" >&2
        exit 1
        ;;
esac
