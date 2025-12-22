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

# Directory paths
CHAPTERS_META_DIR="$REPO_ROOT/.novelkit/chapters"  # Meta-space: plan, history, reports
CHAPTERS_USER_DIR="$REPO_ROOT/chapters"             # User-space: chapter content
CONFIG_FILE="$REPO_ROOT/.novelkit/memory/config.json"
PLAN_TEMPLATE="$REPO_ROOT/.novelkit/templates/chapter.md"

# Ensure directories exist
mkdir -p "$CHAPTERS_META_DIR"
mkdir -p "$CHAPTERS_USER_DIR"

# Get user-space chapter file path from chapter ID and number
get_chapter_user_file() {
    local chapter_id="$1"
    local chapter_number="$2"
    
    # Extract number from chapter_id if number not provided
    if [ -z "$chapter_number" ]; then
        chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    fi
    
    # Format as chapter-001.md
    printf "chapter-%03d.md" "$chapter_number"
}

# Get next chapter ID
get_next_chapter_id() {
    local highest=0
    if [ -d "$CHAPTERS_META_DIR" ]; then
        for dir in "$CHAPTERS_META_DIR"/chapter-*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            number=$(echo "$dirname" | grep -o '[0-9]\+$' || echo "0")
            number=$((10#$number))
            if [ "$number" -gt "$highest" ]; then
                highest=$number
            fi
        done
    fi
    printf "chapter-%03d" $((highest + 1))
}

# Get next chapter number
get_next_chapter_number() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "1"
        return
    fi
    
    local current_number=$(jq -r '.current_chapter.number // .novel.total_chapters // 0' "$CONFIG_FILE" 2>/dev/null || echo "0")
    echo $((current_number + 1))
}

# Get current chapter from config
get_current_chapter() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        return
    fi
    jq -r '.current_chapter.id // ""' "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Get latest completed chapter
get_latest_completed_chapter() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        return
    fi
    
    # Find latest completed chapter from history
    local latest=$(jq -r '.history.chapter_creations[-1].chapter_id // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    echo "$latest"
}

# Parse JSON output helper
json_output() {
    local action="$1"
    shift
    case "$action" in
        "plan")
            local chapter_id="$1"
            local chapter_number="$2"
            local plan_file="$3"
            cat <<EOF
{
  "action": "plan",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_number": $chapter_number,
  "plan_file": "$plan_file",
  "chapters_meta_dir": "$CHAPTERS_META_DIR"
}
EOF
            ;;
        "write")
            local chapter_id="$1"
            local chapter_file="$2"
            local word_count="$3"
            cat <<EOF
{
  "action": "write",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_file": "$chapter_file",
  "word_count": $word_count
}
EOF
            ;;
        "polish")
            local chapter_id="$1"
            local chapter_file="$2"
            local word_count_before="$3"
            local word_count_after="$4"
            cat <<EOF
{
  "action": "polish",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_file": "$chapter_file",
  "word_count_before": $word_count_before,
  "word_count_after": $word_count_after
}
EOF
            ;;
        "confirm")
            local chapter_id="$1"
            local chapter_file="$2"
            local word_count="$3"
            cat <<EOF
{
  "action": "confirm",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_file": "$chapter_file",
  "word_count": $word_count,
  "status": "completed"
}
EOF
            ;;
        "show")
            local chapter_id="$1"
            local chapter_file="$2"
            cat <<EOF
{
  "action": "show",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_file": "$chapter_file"
}
EOF
            ;;
        "review")
            local chapter_id="$1"
            local chapter_file="$2"
            local review_report="$3"
            cat <<EOF
{
  "action": "review",
  "success": true,
  "chapter_id": "$chapter_id",
  "chapter_file": "$chapter_file",
  "review_report": "$review_report"
}
EOF
            ;;
        "list")
            local json_chapters="$1"
            cat <<EOF
{
  "action": "list",
  "success": true,
  "chapters": $json_chapters,
  "current_chapter": "$(get_current_chapter)"
}
EOF
            ;;
        *)
            echo "{\"action\":\"$action\",\"success\":false,\"error\":\"Unknown action\"}" >&2
            exit 1
            ;;
    esac
}

# Action: Plan
action_plan() {
    local chapter_id=$(get_next_chapter_id)
    local chapter_number=$(get_next_chapter_number)
    local chapter_dir="$CHAPTERS_META_DIR/$chapter_id"
    
    mkdir -p "$chapter_dir"
    
    local plan_file="$chapter_dir/plan.md"
    
    # Create plan file placeholder (AI will fill it)
    if [ ! -f "$plan_file" ]; then
        cat > "$plan_file" <<EOF
# Chapter Planning: $chapter_id

**Chapter Number**: $chapter_number  
**Status**: Planned  
**Created**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Plot Summary

[To be filled by AI through interactive interview]

## Characters

[To be filled by AI]

## Location

[To be filled by AI]

## Key Events

[To be filled by AI]

## Foreshadowing & Clues

[To be filled by AI]

## Connections

[To be filled by AI]

EOF
    fi
    
    json_output "plan" "$chapter_id" "$chapter_number" "$plan_file"
}

# Action: Write
action_write() {
    local chapter_id="$1"
    if [ -z "$chapter_id" ]; then
        chapter_id=$(get_current_chapter)
    fi
    
    if [ -z "$chapter_id" ]; then
        echo "{\"action\":\"write\",\"success\":false,\"error\":\"No chapter ID provided and no current chapter\"}" >&2
        exit 1
    fi
    
    # Get chapter number from config or extract from ID
    local chapter_number=$(jq -r ".current_chapter.number // 0" "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$chapter_number" = "0" ] || [ "$chapter_number" = "null" ]; then
        chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    fi
    
    local chapter_dir="$CHAPTERS_META_DIR/$chapter_id"
    local plan_file="$chapter_dir/plan.md"
    local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
    
    if [ ! -f "$plan_file" ]; then
        echo "{\"action\":\"write\",\"success\":false,\"error\":\"Plan file not found: $plan_file\"}" >&2
        exit 1
    fi
    
    # Create chapter file placeholder (AI will fill it)
    if [ ! -f "$chapter_file" ]; then
        cat > "$chapter_file" <<EOF
# Chapter Content: $chapter_id

**Status**: Written  
**Created**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

[To be filled by AI based on plan and writer style]

EOF
    fi
    
    # Count words (rough estimate)
    local word_count=$(wc -w < "$chapter_file" 2>/dev/null || echo "0")
    
    json_output "write" "$chapter_id" "$chapter_file" "$word_count"
}

# Action: Polish
action_polish() {
    local chapter_id="$1"
    if [ -z "$chapter_id" ]; then
        chapter_id=$(get_current_chapter)
    fi
    
    if [ -z "$chapter_id" ]; then
        echo "{\"action\":\"polish\",\"success\":false,\"error\":\"No chapter ID provided and no current chapter\"}" >&2
        exit 1
    fi
    
    # Get chapter number from config
    local chapter_number=$(jq -r ".current_chapter.number // 0" "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$chapter_number" = "0" ] || [ "$chapter_number" = "null" ]; then
        chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    fi
    
    local chapter_dir="$CHAPTERS_META_DIR/$chapter_id"
    local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
    
    if [ ! -f "$chapter_file" ]; then
        echo "{\"action\":\"polish\",\"success\":false,\"error\":\"Chapter file not found: $chapter_file\"}" >&2
        exit 1
    fi
    
    # Count words before
    local word_count_before=$(wc -w < "$chapter_file" 2>/dev/null || echo "0")
    
    # Create polish history file
    local polish_history="$chapter_dir/polish-history.md"
    if [ ! -f "$polish_history" ]; then
        cat > "$polish_history" <<EOF
# Polishing History

## $(date -u +"%Y-%m-%dT%H:%M:%SZ") - Polish Session 1

[To be filled by AI]

EOF
    fi
    
    # Word count after will be updated by AI
    local word_count_after="$word_count_before"
    
    json_output "polish" "$chapter_id" "$chapter_file" "$word_count_before" "$word_count_after"
}

# Action: Confirm
action_confirm() {
    
    local chapter_id="$1"
    if [ -z "$chapter_id" ]; then
        chapter_id=$(get_current_chapter)
    fi
    
    if [ -z "$chapter_id" ]; then
        echo "{\"action\":\"confirm\",\"success\":false,\"error\":\"No chapter ID provided and no current chapter\"}" >&2
        exit 1
    fi
    
    # Get chapter number from config
    local chapter_number=$(jq -r ".current_chapter.number // 0" "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$chapter_number" = "0" ] || [ "$chapter_number" = "null" ]; then
        chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    fi
    
    local chapter_dir="$CHAPTERS_META_DIR/$chapter_id"
    local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
    
    if [ ! -f "$chapter_file" ]; then
        echo "{\"action\":\"confirm\",\"success\":false,\"error\":\"Chapter file not found: $chapter_file\"}" >&2
        exit 1
    fi
    
    # Count words
    local word_count=$(wc -w < "$chapter_file" 2>/dev/null || echo "0")
    
    json_output "confirm" "$chapter_id" "$chapter_file" "$word_count"
}

# Action: Show
action_show() {
    local search="$*"
    local chapter_id=""
    
    if [ -z "$search" ]; then
        chapter_id=$(get_current_chapter)
    else
        # Try to find chapter
        if [ -d "$CHAPTERS_META_DIR/$search" ]; then
            chapter_id="$search"
        else
            # Try to find by number or partial match
            for dir in "$CHAPTERS_META_DIR"/chapter-*; do
                [ -d "$dir" ] || continue
                dirname=$(basename "$dir")
                if echo "$dirname" | grep -q "$search"; then
                    chapter_id="$dirname"
                    break
                fi
            done
        fi
    fi
    
    if [ -z "$chapter_id" ]; then
        echo "{\"action\":\"show\",\"success\":false,\"error\":\"Chapter not found: $search\"}" >&2
        exit 1
    fi
    
    # Try user-space chapter file first, then meta-space plan
    local chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
    if [ ! -f "$chapter_file" ]; then
        chapter_file="$CHAPTERS_META_DIR/$chapter_id/plan.md"
    fi
    
    if [ ! -f "$chapter_file" ]; then
        echo "{\"action\":\"show\",\"success\":false,\"error\":\"Chapter file not found: $chapter_file\"}" >&2
        exit 1
    fi
    
    json_output "show" "$chapter_id" "$chapter_file"
}

# Action: Review
action_review() {
    local chapter_id="$1"
    if [ -z "$chapter_id" ]; then
        chapter_id=$(get_current_chapter)
    fi
    
    if [ -z "$chapter_id" ]; then
        echo "{\"action\":\"review\",\"success\":false,\"error\":\"No chapter ID provided and no current chapter\"}" >&2
        exit 1
    fi
    
    # Get chapter number from config
    local chapter_number=$(jq -r ".current_chapter.number // 0" "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$chapter_number" = "0" ] || [ "$chapter_number" = "null" ]; then
        chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
    fi
    
    local chapter_dir="$CHAPTERS_META_DIR/$chapter_id"
    local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
    
    if [ ! -f "$chapter_file" ]; then
        echo "{\"action\":\"review\",\"success\":false,\"error\":\"Chapter file not found: $chapter_file\"}" >&2
        exit 1
    fi
    
    # Create review report file (in meta-space)
    local review_report="$chapter_dir/review-report.md"
    
    # Count words
    local word_count=$(wc -w < "$chapter_file" 2>/dev/null || echo "0")
    
    json_output "review" "$chapter_id" "$chapter_file" "$review_report"
}

# Action: List
action_list() {
    local chapters_json="[]"
    
    if [ -d "$CHAPTERS_META_DIR" ]; then
        local current=$(get_current_chapter)
        local chapters_array="["
        local first=true
        
        for dir in "$CHAPTERS_META_DIR"/chapter-*; do
            [ -d "$dir" ] || continue
            chapter_id=$(basename "$dir")
            plan_file="$dir/plan.md"
            
            # Get chapter number from plan or extract from ID
            local chapter_number=$(grep -E "^\*\*Chapter Number\*\*:" "$plan_file" 2>/dev/null | sed 's/\*\*Chapter Number\*\*: //' | head -1 | xargs || echo "")
            if [ -z "$chapter_number" ]; then
                chapter_number=$(echo "$chapter_id" | grep -o '[0-9]\+$' || echo "1")
            fi
            
            local chapter_file="$CHAPTERS_USER_DIR/$(get_chapter_user_file "$chapter_id" "$chapter_number")"
            
            local status="planned"
            local word_count=0
            local title=""
            
            if [ -f "$plan_file" ]; then
                title=$(grep -E "^# Chapter" "$plan_file" | head -1 | sed 's/# Chapter.*: //' | xargs || echo "")
            fi
            
            if [ -f "$chapter_file" ]; then
                status="written"
                word_count=$(wc -w < "$chapter_file" 2>/dev/null || echo "0")
            fi
            
            is_current="false"
            [ "$chapter_id" = "$current" ] && is_current="true"
            
            if [ "$first" = true ]; then
                first=false
            else
                chapters_array="$chapters_array,"
            fi
            
            chapters_array="$chapters_array{\"id\":\"$chapter_id\",\"title\":\"$title\",\"number\":\"$chapter_number\",\"status\":\"$status\",\"word_count\":$word_count,\"current\":$is_current}"
        done
        
        chapters_array="$chapters_array]"
        chapters_json="$chapters_array"
    fi
    
    json_output "list" "$chapters_json"
}

# Main
main() {
    # Check config.json exists (should already exist, don't create it)
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"success\":false,\"error\":\"config.json not found in .novelkit/memory/. It should already exist.\"}" >&2
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "$action" in
        "plan")
            action_plan "$@"
            ;;
        "write")
            action_write "$@"
            ;;
        "polish")
            action_polish "$@"
            ;;
        "confirm")
            action_confirm "$@"
            ;;
        "show")
            action_show "$@"
            ;;
        "review")
            action_review "$@"
            ;;
        "list")
            action_list "$@"
            ;;
        *)
            echo "Usage: $0 {plan|write|polish|confirm|review|show|list} [args...]" >&2
            exit 1
            ;;
    esac
}

# Parse JSON arguments if provided
if [ "$1" = "--json" ]; then
    shift
    JSON_ARGS="$1"
    # JSON parsing would go here if needed
fi

main "$@"

