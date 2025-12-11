#!/bin/bash
set -Eeuo pipefail

# Usage: ./validate-config.sh <config-file> <schema-file>
# Example: ./validate-config.sh live/ios-config/ios-config.json schemas/ios/schema.json

CONFIG_FILE="${1:-}"
SCHEMA_FILE="${2:-}"
MAIN_BRANCH="${3:-main}"

# Validate arguments
if [ -z "$CONFIG_FILE" ] || [ -z "$SCHEMA_FILE" ]; then
    echo "Usage: $0 <config-file> <schema-file> [main-branch]"
    echo "Example: $0 live/ios-config/ios-config.json schemas/ios/schema.json main"
    exit 1
fi

# 1. Validate JSON schema
npm i -g ajv-cli

echo "### Validating JSON Schema" >> $GITHUB_STEP_SUMMARY

# Capture output and fail on non-zero exit
if ! AJV_OUTPUT=$(ajv validate -s "$SCHEMA_FILE" -d "$CONFIG_FILE" --all-errors 2>&1); then
  echo "$AJV_OUTPUT"  # Show in logs

  echo "::error file=$CONFIG_FILE,title=Schema Validation Failed::${AJV_OUTPUT//$'\n'/ }"

  echo "❌ **Schema Validation Failed**" >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY
  echo "$AJV_OUTPUT" | grep -v 'npm warn' >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY

  echo "VALIDATION_ERROR=schema" >> $GITHUB_ENV
  echo "ERROR_MESSAGE<<EOF" >> $GITHUB_ENV
  echo "$AJV_OUTPUT" | grep -v 'npm warn' >> $GITHUB_ENV
  echo "EOF" >> $GITHUB_ENV
  exit 1
fi

echo "✅ Schema validation passed" >> $GITHUB_STEP_SUMMARY

# 2. Check version was incremented
echo "### Version Check" >> $GITHUB_STEP_SUMMARY

if git diff --name-only origin/$MAIN_BRANCH...HEAD | grep -Fx "$CONFIG_FILE" >/dev/null; then
  PR_VERSION=$(jq -r '.version' $CONFIG_FILE)
  MAIN_VERSION=$(git show origin/$MAIN_BRANCH:$CONFIG_FILE | jq -r '.version')

  echo "Main: v$MAIN_VERSION → PR: v$PR_VERSION" >> $GITHUB_STEP_SUMMARY

  if [ "$PR_VERSION" -le "$MAIN_VERSION" ]; then
    echo "::error file=$CONFIG_FILE,title=Version Not Incremented::Version must be incremented. Main=$MAIN_VERSION, PR=$PR_VERSION"

    echo "❌ **Version not incremented!**" >> $GITHUB_STEP_SUMMARY

    echo "VALIDATION_ERROR=version" >> $GITHUB_ENV
    echo "ERROR_MESSAGE=Version must be incremented! Main branch has version $MAIN_VERSION, your PR has version $PR_VERSION" >> $GITHUB_ENV
    exit 1
  fi

  echo "✅ Version correctly incremented" >> $GITHUB_STEP_SUMMARY
else
  echo "Config file unchanged in this PR; skipping version check." >> $GITHUB_STEP_SUMMARY
fi

# 3. Check all rule references exist
echo "### Rule Reference Check" >> $GITHUB_STEP_SUMMARY

VALIDATION_ERROR=$(jq '
  (.rules | map(.id)) as $rule_ids |
  .messages | map(
    . as $msg |
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
  ) | .[]
' $CONFIG_FILE)

if [ ! -z "$VALIDATION_ERROR" ]; then
  echo "::error file=$CONFIG_FILE,title=Invalid Rule References::$VALIDATION_ERROR"

  echo "❌ **Invalid rule references found:**" >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY
  echo "$VALIDATION_ERROR" >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY

  echo "VALIDATION_ERROR=rules" >> $GITHUB_ENV
  echo "ERROR_MESSAGE<<EOF" >> $GITHUB_ENV
  echo "$VALIDATION_ERROR" >> $GITHUB_ENV
  echo "EOF" >> $GITHUB_ENV
  exit 1
fi

echo "✅ All rule references are valid" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY
echo "### ✅ All validations passed!" >> $GITHUB_STEP_SUMMARY
