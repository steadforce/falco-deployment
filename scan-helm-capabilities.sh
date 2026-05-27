#!/bin/bash
set -e

# Checks
command -v helm >/dev/null 2>&1 || { echo >&2 "Helm is required but not installed. Aborting."; exit 1; }

CHART_DIR=${1:-"."}

if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
    echo "Error: Chart.yaml not found in $CHART_DIR"
    exit 1
fi

echo "🔍 Analyzing Chart in: $CHART_DIR"

# Create a temporary directory
WORK_DIR=$(mktemp -d)
echo "📂 Working in temp directory: $WORK_DIR"

# Cleanup on exit
trap 'rm -rf -- "$WORK_DIR"' EXIT

# Copy the chart to temp dir (including hidden files)
cp -r "$CHART_DIR/." "$WORK_DIR/"

pushd "$WORK_DIR" > /dev/null

echo "⬇️  Downloading dependencies..."
helm dependency update > /dev/null 2>&1

echo "📦 Extracting all charts (recursive)..."
while [ -n "$(find . -name '*.tgz' -print -quit)" ]; do
    find . -name "*.tgz" -type f | while read -r tarball; do
        # Validate archive contents to prevent path traversal before extraction
        if tar -tzf "$tarball" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
            echo "⚠️  Skipping suspicious archive with unsafe paths: $tarball" >&2
            rm "$tarball"
            continue
        fi
        tar -xzf "$tarball" -C "$(dirname "$tarball")"
        rm "$tarball"
    done
done

echo "🔎 Scanning templates for Capabilities.APIVersions.Has..."
echo "---------------------------------------------------"
echo "✅ Found the following conditional API checks:"
echo "---------------------------------------------------"

# File to store just the clean API strings
CLEAN_LIST_FILE="clean_apis.txt"
touch "$CLEAN_LIST_FILE"

# 1. Find lines with matches using grep -rn
# We save this to a temp file to read line-by-line safely
grep -rn \
    --include="*.yaml" \
    --include="*.yml" \
    --include="*.tpl" \
    -E "\.Capabilities\.APIVersions\.Has" . > raw_matches.txt || true

if [ ! -s raw_matches.txt ]; then
    echo "No explicit '.Capabilities.APIVersions.Has' checks found."
else
    # Read the raw grep output line by line
    while IFS= read -r line; do
        # Extract File and Line (fields 1 and 2)
        FILE_LOC=$(echo "$line" | cut -d: -f1-2)
        
        # Extract the content (field 3 onwards) to ignore the filename prefix in regex
        CONTENT=$(echo "$line" | cut -d: -f3-)

        # Find ALL matches in this specific line (handles multiple checks on one line)
        # grep -o puts each match on a new line
        MATCHES_IN_LINE=$(echo "$CONTENT" \
            | grep -oE '\.Capabilities\.APIVersions\.Has[[:space:](]*"[^"]+"' \
            | sed -E 's/.*"([^"]+)".*/\1/')

        # Loop through the matches found on this single line
        while IFS= read -r api; do
            if [ -n "$api" ]; then
                # Remove ./ prefix for cleaner output
                CLEAN_LOC=${FILE_LOC#./}
                echo "📄 $CLEAN_LOC"
                echo "   └── 🏷️  $api"
                echo "$api" >> "$CLEAN_LIST_FILE"
            fi
        done <<< "$MATCHES_IN_LINE"

    done < raw_matches.txt
fi

echo ""
echo "---------------------------------------------------"
echo "💡 Suggestion for your helm-config.yaml:"
echo "---------------------------------------------------"

if [ -s "$CLEAN_LIST_FILE" ]; then
    # Sort, Unique, and format as YAML list
    sort "$CLEAN_LIST_FILE" | uniq | sed 's/^/- /'
else
    echo "# No APIs found."
fi

popd > /dev/null