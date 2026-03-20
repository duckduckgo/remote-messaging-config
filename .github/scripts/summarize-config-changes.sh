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

# Try to get the previous version of the file
if git show "HEAD~1:${config_path}" > "$old_config" 2>/dev/null; then
  has_previous=true
else
  has_previous=false
fi

# Extract sorted message IDs from a config file
extract_ids() {
  jq -r '.messages[]?.id' "$1" | sort -u
}

# Compute a SHA-256 over all message objects matching a given ID
message_hash() {
  jq -c --arg id "$1" '[.messages[] | select(.id == $id)]' "$2" | shasum -a 256 | awk '{print $1}'
}

current_ids=$(extract_ids "$config_path")

description=""

if [ "$has_previous" = true ]; then
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
    description+="**Added messages:**"$'\n'
    while IFS= read -r msg_id; do
      description+="- \`${msg_id}\`"$'\n'
    done <<< "$added"
    description+=$'\n'
  fi

  if [ -n "$removed" ]; then
    description+="**Removed messages:**"$'\n'
    while IFS= read -r msg_id; do
      description+="- \`${msg_id}\`"$'\n'
    done <<< "$removed"
    description+=$'\n'
  fi

  if [ -n "$modified" ]; then
    description+="**Modified messages:**"$'\n'
    while IFS= read -r msg_id; do
      description+="- \`${msg_id}\`"$'\n'
    done <<< "$modified"
    description+=$'\n'
  fi

  if [ -z "$added" ] && [ -z "$removed" ] && [ -z "$modified" ]; then
    old_version=$(jq -r '.version' "$old_config")
    description+="No message changes. Version bumped from ${old_version} to ${version}."$'\n'
  fi
else
  # No previous commit available — list all current message IDs
  if [ -n "$current_ids" ]; then
    description+="**Current messages (no previous version available):**"$'\n'
    while IFS= read -r msg_id; do
      description+="- \`${msg_id}\`"$'\n'
    done <<< "$current_ids"
    description+=$'\n'
  else
    description+="Initial config with no messages."$'\n'
  fi
fi

commit_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
description+=$'\n'"[View commit](${commit_url})"

task_name="${platform} RMF Config Updated (v${version})"

{
  echo "task_name=${task_name}"
  echo "task_description<<DESCRIPTION_EOF"
  echo "$description"
  echo "DESCRIPTION_EOF"
} >> "$GITHUB_OUTPUT"
