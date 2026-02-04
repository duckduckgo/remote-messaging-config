#!/bin/bash
set -Eeuo pipefail

# Usage: .github/scripts/validate-config.sh <config-file> <schema-file>
# Example: .github/scripts/validate-config.sh live/ios-config/ios-config.json schemas/ios/schema.json
# Example: .github/scripts/validate-config.sh live/macos-config/macos-config.json schemas/macos/schema.json

CONFIG_FILE="${1:-}"
SCHEMA_FILE="${2:-}"
MAIN_BRANCH="${3:-main}"

# Support local execution (these are GitHub Actions env vars)
IS_CI="${GITHUB_ACTIONS:-false}"
GITHUB_STEP_SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"
GITHUB_ENV_PATH="${GITHUB_ENV:-}"

is_ci() { [ "$IS_CI" = "true" ]; }

timestamp() {
  # ISO8601-ish, stable across macOS/GNU date
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  local level="$1"; shift
  printf '[%s] %-5s %s\n' "$(timestamp)" "$level" "$*"
}

log_section() {
  printf '\n== %s ==\n' "$*"
}

ci_summary() {
  is_ci || return 0
  [ -n "$GITHUB_STEP_SUMMARY_PATH" ] || return 0
  printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY_PATH"
}

ci_env_set() {
  is_ci || return 0
  [ -n "$GITHUB_ENV_PATH" ] || return 0
  printf '%s\n' "$*" >> "$GITHUB_ENV_PATH"
}

ci_annotate_error() {
  is_ci || return 0
  # GitHub Actions annotation format
  # shellcheck disable=SC2028
  echo "::error file=$1,title=$2::$3"
}

require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log ERROR "Missing dependency: $cmd"
    if [ -n "$hint" ]; then
      log ERROR "$hint"
    fi
    return 1
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    log ERROR "$label not found: $path"
    return 1
  fi
}

assert_valid_json() {
  local path="$1"
  local label="$2"
  local err
  err="$(mktemp)"
  if ! jq -e . "$path" >/dev/null 2>"$err"; then
    print_block "❌ Invalid JSON ($label)" "$(cat "$err")"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
}

truncate_lines() {
  local input="$1"
  local max_lines="$2"

  local total_lines
  total_lines="$(printf '%s\n' "$input" | wc -l | tr -d ' ')"
  if [ "$total_lines" -le "$max_lines" ]; then
    printf '%s' "$input"
    return 0
  fi

  printf '%s\n...\n(truncated to %s lines)\n' "$(printf '%s\n' "$input" | head -n "$max_lines")" "$max_lines"
}

format_ajv_errors_for_humans() {
  # AJV sometimes emits multiple errors as a single comma-separated line, e.g.:
  #   data/... must ..., data/... must ...
  #
  # Implement splitting + cleanup in awk (portable on macOS/BSD) rather than relying on sed \n behavior.
  awk '
    function flush() {
      if (prev != "") print prev
      prev = ""
    }

    function should_drop_structural(s) {
      return (s ~ / must match "then" schema$/ ||
              s ~ / must match "else" schema$/ ||
              s ~ / must match "allOf" schema$/ ||
              s ~ / must match "anyOf" schema$/ ||
              s ~ / must match "oneOf" schema$/)
    }

    function emit_piece(s) {
      sub(/^[[:space:]]+/, "", s) # trim leading whitespace
      if (s == "") return
      if (should_drop_structural(s)) return

      # Attach detail lines to the previous primary error line when possible.
      if (s ~ /additionalProperty:/ && prev ~ /must NOT have additional properties/) {
        prev = prev " (" s ")"
        return
      }
      if (s ~ /missingProperty:/ && prev ~ /must have required property/) {
        prev = prev " (" s ")"
        return
      }
      if (s ~ /pattern:/ && prev ~ /must match pattern/) {
        prev = prev " (" s ")"
        return
      }

      flush()
      prev = s
    }

    function split_and_emit(line,   s) {
      s = line
      while (match(s, /,[[:space:]]*(data\/|schema\.|data#\/)/)) {
        emit_piece(substr(s, 1, RSTART - 1))
        s = substr(s, RSTART + 1)    # drop the comma
        sub(/^[[:space:]]+/, "", s)  # drop spaces after comma
      }
      emit_piece(s)
    }

    { split_and_emit($0) }
    END { flush() }
  '
}

# Replace array indices with IDs in error messages for readability
# e.g., "data/rules/9/attributes" -> "data/rules[id=42]/attributes"
humanize_errors() {
  local input="$1"
  local config="$2"
  
  echo "$input" | while IFS= read -r line; do
    local result="$line"
    
    # Replace rules/N with rules[id=X]
    if [[ "$result" =~ rules/([0-9]+) ]]; then
      local idx="${BASH_REMATCH[1]}"
      local rule_id
      rule_id="$(jq -r ".rules[$idx].id // \"$idx\"" "$config")"
      result="${result//rules\/$idx/rules[id=$rule_id]}"
    fi
    
    # Replace messages/N with messages[id=X]
    if [[ "$result" =~ messages/([0-9]+) ]]; then
      local idx="${BASH_REMATCH[1]}"
      local msg_id
      msg_id="$(jq -r ".messages[$idx].id // \"$idx\"" "$config")"
      result="${result//messages\/$idx/messages[id=\"$msg_id\"]}"
    fi
    
    echo "$result"
  done
}

print_block() {
  # Print a pre-formatted block (used for schema/rule errors)
  local title="$1"
  local body="$2"

  log_section "$title"
  if [ -n "$body" ]; then
    printf '%s\n' "$body"
  else
    printf '%s\n' "(no details available)"
  fi
}

# Validate arguments
if [ -z "$CONFIG_FILE" ] || [ -z "$SCHEMA_FILE" ]; then
    log ERROR "Usage: $0 <config-file> <schema-file> [main-branch]"
    log ERROR "Example: .github/scripts/validate-config.sh live/ios-config/ios-config.json schemas/ios/schema.json main"
    exit 1
fi

# Preflight checks (fail fast with friendly errors)
log_section "Preflight"
if ! require_cmd jq "Install: macOS: brew install jq  |  Ubuntu: sudo apt-get install -y jq"; then
  exit 2
fi
if ! require_cmd npx "Install Node.js (includes npx): https://nodejs.org/"; then
  exit 2
fi
if ! assert_file_exists "$CONFIG_FILE" "Config file"; then
  exit 2
fi
if ! assert_file_exists "$SCHEMA_FILE" "Schema file"; then
  exit 2
fi
if ! assert_valid_json "$CONFIG_FILE" "config"; then
  ci_annotate_error "$CONFIG_FILE" "Invalid JSON" "Config file is not valid JSON"
  exit 2
fi
if ! assert_valid_json "$SCHEMA_FILE" "schema"; then
  ci_annotate_error "$SCHEMA_FILE" "Invalid JSON" "Schema file is not valid JSON"
  exit 2
fi
log INFO "✅ Preflight checks passed"

# 1. Validate JSON schema
log_section "Schema validation"
log INFO "Validating config against schema"
AJV_CLI_VERSION="5.0.0"
AJV_MAX_ERROR_LINES=200
RMF_VALIDATION_VERBOSE="${RMF_VALIDATION_VERBOSE:-1}"
AJV_VERBOSE_ARG=""
if [ "$RMF_VALIDATION_VERBOSE" = "1" ]; then
  AJV_VERBOSE_ARG="--verbose"
fi

ci_summary "### Validating JSON Schema"

# Capture output and fail on non-zero exit
if ! AJV_OUTPUT=$(
  NPM_CONFIG_UPDATE_NOTIFIER=false \
  NPM_CONFIG_FUND=false \
  NPM_CONFIG_AUDIT=false \
  npx --yes "ajv-cli@$AJV_CLI_VERSION" validate -s "$SCHEMA_FILE" -d "$CONFIG_FILE" --all-errors --errors=text ${AJV_VERBOSE_ARG:+$AJV_VERBOSE_ARG} 2>&1
); then
  # Make errors more readable by replacing array indices with IDs
  # NOTE: grep can exit 1 when it filters everything; don't let `set -e` kill the script.
  READABLE_OUTPUT="$(
    humanize_errors "$AJV_OUTPUT" "$CONFIG_FILE" |
      grep -vE '^(npm (notice|warn)|npm ERR!|npx:)' |
      format_ajv_errors_for_humans || true
  )"
  if [ -z "$READABLE_OUTPUT" ]; then
    READABLE_OUTPUT="$AJV_OUTPUT"
  fi
  
  DISPLAY_OUTPUT="$(truncate_lines "$READABLE_OUTPUT" "$AJV_MAX_ERROR_LINES")"
  print_block "❌ Schema validation failed" "$DISPLAY_OUTPUT"

  ci_annotate_error "$CONFIG_FILE" "Schema Validation Failed" "See details in job summary"

  ci_summary "❌ **Schema Validation Failed**"
  ci_summary '```'
  ci_summary "$DISPLAY_OUTPUT"
  ci_summary '```'

  ci_env_set "VALIDATION_ERROR=schema"
  ci_env_set "ERROR_MESSAGE<<EOF"
  ci_env_set "$DISPLAY_OUTPUT"
  ci_env_set "EOF"
  exit 1
fi

log INFO "✅ Schema validation passed"
ci_summary "✅ Schema validation passed"

# 2. Check version was incremented
log_section "Version check"
log INFO "Checking version increment (only when config file changed in PR)"
ci_summary "### Version Check"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log WARN "Not a git checkout; skipping version check"
  ci_summary "Not a git checkout; skipping version check."
elif ! git show-ref --verify --quiet "refs/remotes/origin/$MAIN_BRANCH"; then
  log WARN "origin/$MAIN_BRANCH not available; skipping version check (run: git fetch origin $MAIN_BRANCH)"
  ci_summary "origin/$MAIN_BRANCH not available; skipping version check."
elif git diff --name-only "origin/$MAIN_BRANCH...HEAD" | grep -Fx "$CONFIG_FILE" >/dev/null; then
  PR_VERSION="$(jq -r '.version' "$CONFIG_FILE")"
  MAIN_VERSION="$(git show "origin/$MAIN_BRANCH:$CONFIG_FILE" | jq -r '.version')"

  log INFO "Main: v$MAIN_VERSION → PR: v$PR_VERSION"
  ci_summary "Main: v$MAIN_VERSION → PR: v$PR_VERSION"

  if [ "$PR_VERSION" -le "$MAIN_VERSION" ]; then
    print_block "❌ Version not incremented" "Expected v$((MAIN_VERSION + 1)) or higher, got v$PR_VERSION"

    ci_annotate_error "$CONFIG_FILE" "Version Not Incremented" "Expected v$((MAIN_VERSION + 1)) or higher, got v$PR_VERSION"

    ci_summary "❌ **Version not incremented!**"

    ci_env_set "VALIDATION_ERROR=version"
    ci_env_set "ERROR_MESSAGE=Version must be incremented! Main branch has version $MAIN_VERSION, your PR has version $PR_VERSION"
    exit 1
  fi

  log INFO "✅ Version correctly incremented"
  ci_summary "✅ Version correctly incremented"
else
  log INFO "Config file unchanged; skipping version check"
  ci_summary "Config file unchanged in this PR; skipping version check."
fi

# 3. Check all rule references exist
log_section "Rule reference check"
log INFO "Ensuring message matchingRules/exclusionRules refer to existing rule IDs"
ci_summary "### Rule Reference Check"

VALIDATION_ERROR=$(jq '
  (.rules | map(.id)) as $rule_ids |
  (.messages // []) | map(
    . as $msg |
    (
      ((.matchingRules // []) - $rule_ids |
        if length > 0 then
          "Message \"" + $msg.id + "\" references non-existent matchingRules: " + (. | @json)
        else empty end
      ),
      ((.exclusionRules // []) - $rule_ids |
        if length > 0 then
          "Message \"" + $msg.id + "\" references non-existent exclusionRules: " + (. | @json)
        else empty end
      )
    ),
    (
      ((.content.listItems // []) | to_entries[]? | .key) as $i |
      ((.content.listItems // [])[$i]) as $item |
      (
        (($item.matchingRules // []) - $rule_ids |
          if length > 0 then
            "Message \"" + $msg.id + "\" listItems[" + ($i|tostring) + "] references non-existent matchingRules: " + (. | @json)
          else empty end
        ),
        (($item.exclusionRules // []) - $rule_ids |
          if length > 0 then
            "Message \"" + $msg.id + "\" listItems[" + ($i|tostring) + "] references non-existent exclusionRules: " + (. | @json)
          else empty end
        )
      )
    )
  ) | flatten | .[]
' "$CONFIG_FILE")

if [ ! -z "$VALIDATION_ERROR" ]; then
  print_block "❌ Invalid rule references found" "$VALIDATION_ERROR"
  RULE_IDS_JSON="$(jq -c '(.rules | map(.id) | sort)' "$CONFIG_FILE")"
  log INFO "Valid rule IDs in this config: $RULE_IDS_JSON"

  ci_annotate_error "$CONFIG_FILE" "Invalid Rule References" "See details in job summary"

  ci_summary "❌ **Invalid rule references found:**"
  ci_summary '```'
  ci_summary "$VALIDATION_ERROR"
  ci_summary '```'
  ci_summary ""
  ci_summary "**Valid rule IDs:** \`$RULE_IDS_JSON\`"

  ci_env_set "VALIDATION_ERROR=rules"
  ci_env_set "ERROR_MESSAGE<<EOF"
  ci_env_set "$VALIDATION_ERROR"
  ci_env_set "EOF"
  exit 1
fi

log INFO "✅ All rule references are valid"
ci_summary "✅ All rule references are valid"
ci_summary ""

# 4. Check for orphaned rules (rules that are never referenced)
log_section "Orphan rule check"
log INFO "Ensuring all rules are referenced by at least one message"
ci_summary "### Orphan Rule Check"

ORPHAN_RULE_IDS_JSON="$(jq -c '
  (.rules | map(.id)) as $rule_ids |
  (
    [
      .messages[]? |
        (.matchingRules // []),
        (.exclusionRules // []),
        (
          (.content.listItems // [])
          | map(.matchingRules // [])
          | add
        ) // [],
        (
          (.content.listItems // [])
          | map(.exclusionRules // [])
          | add
        ) // []
    ] | flatten
  ) as $refs |
  ($rule_ids - ($refs | unique)) | sort
' "$CONFIG_FILE")"

if [ "$ORPHAN_RULE_IDS_JSON" != "[]" ]; then
  print_block "❌ Orphaned rules found" "Rule IDs are defined but never referenced by any message: $ORPHAN_RULE_IDS_JSON"

  ci_annotate_error "$CONFIG_FILE" "Orphaned Rules" "Rules are defined but never referenced by any message"

  ci_summary "❌ **Orphaned rules found**"
  ci_summary ""
  ci_summary "**Rule IDs:** \`$ORPHAN_RULE_IDS_JSON\`"
  ci_summary ""
  ci_summary "**How to fix:**"
  ci_summary "- Remove the unused rule(s), or"
  ci_summary "- Reference them from a message's \`matchingRules\` / \`exclusionRules\`."

  ci_env_set "VALIDATION_ERROR=orphan_rules"
  ci_env_set "ERROR_MESSAGE=Orphaned rules (defined but never referenced): $ORPHAN_RULE_IDS_JSON"
  exit 1
fi

log INFO "✅ No orphaned rules found"
ci_summary "✅ No orphaned rules found"
ci_summary ""
ci_summary "### ✅ All validations passed!"

log_section "Done"
log INFO "✅ All validations passed!"
