#!/bin/bash
set -euo pipefail

config_path="${1:?Usage: summarize-config-changes.sh <config-file-path>}"

# Derive platform label from path (e.g. "live/ios-config/..." → "iOS")
case "$config_path" in
  *ios-config*)  platform="iOS" ;;
  *macos-config*) platform="macOS" ;;
  *)             platform="Unknown" ;;
esac

version=$(jq -r '.version' "$config_path")

old_config=$(mktemp)
trap 'rm -f "$old_config"' EXIT

git show "HEAD~1:${config_path}" > "$old_config"

# Extract sorted message IDs from a config file
extract_ids() {
  jq -r '.messages[]?.id' "$1" | sort -u
}

# Compute a SHA-256 over all message objects matching a given ID
message_hash() {
  jq -c --arg id "$1" '[.messages[] | select(.id == $id)]' "$2" | shasum -a 256 | awk '{print $1}'
}

# Build a plaintext list of message IDs
build_id_list() {
  local ids="$1"
  while IFS= read -r msg_id; do
    echo "- ${msg_id}"
  done <<< "$ids"
}

current_ids=$(extract_ids "$config_path")

description=""

old_ids=$(extract_ids "$old_config")

added=$(comm -23 <(echo "$current_ids") <(echo "$old_ids") | grep -v '^$' || true)
removed=$(comm -13 <(echo "$current_ids") <(echo "$old_ids") | grep -v '^$' || true)
common=$(comm -12 <(echo "$current_ids") <(echo "$old_ids") | grep -v '^$' || true)

modified=""
if [ -n "$common" ]; then
  while IFS= read -r msg_id; do
    old_hash=$(message_hash "$msg_id" "$old_config")
    new_hash=$(message_hash "$msg_id" "$config_path")
    if [ "$old_hash" != "$new_hash" ]; then
      modified="${modified}${msg_id}"$'\n'
    fi
  done <<< "$common"
  modified=$(echo "$modified" | grep -v '^$' || true)
fi

if [ -n "$added" ]; then
  description+="Added messages:"$'\n'
  description+="$(build_id_list "$added")"$'\n\n'
fi

if [ -n "$removed" ]; then
  description+="Removed messages:"$'\n'
  description+="$(build_id_list "$removed")"$'\n\n'
fi

if [ -n "$modified" ]; then
  description+="Modified messages:"$'\n'
  description+="$(build_id_list "$modified")"$'\n\n'
fi

if [ -z "$added" ] && [ -z "$removed" ] && [ -z "$modified" ]; then
  old_version=$(jq -r '.version' "$old_config")
  description+="No message changes. Version bumped from ${old_version} to ${version}."$'\n\n'
fi

commit_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
description+="${commit_url}"

task_name="${platform} RMF Config Updated (v${version})"

{
  echo "task_name=${task_name}"
  echo "task_description<<DESCRIPTION_EOF"
  echo "$description"
  echo "DESCRIPTION_EOF"
} >> "$GITHUB_OUTPUT"
