#!/usr/bin/env bash
# ==============================================================================
# common.sh - Shared library for Java Server Architecture Review scanning tool
#
# This file is sourced by all check modules. It provides:
#   - JSON output functions (findings emitted to stdout)
#   - File scanning helpers (find Java, XML, config files)
#   - Text processing utilities
#   - Logging functions (all write to stderr to avoid polluting JSON output)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Compatibility: macOS, Linux, Windows Git Bash (POSIX-compatible where possible)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# JSON Output Functions
# ==============================================================================

# json_escape STRING
#   Escape a string for safe inclusion in a JSON value.
#   Handles: backslashes, double quotes, newlines, carriage returns, tabs,
#   form feeds, backspaces.
#
# Usage:
#   escaped=$(json_escape "$raw_string")
json_escape() {
    local s="${1:-}"
    # Order matters: backslash first, then other escapes
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\x08'/\\b}"
    s="${s//$'\x0c'/\\f}"
    printf '%s' "$s"
}

# json_finding ID TYPE SEVERITY DIMENSION DIM_NAME TITLE FILE LINE CODE SUGGESTION
#   Output a single finding as a JSON object to stdout.
#
#   Arguments:
#     ID         - Check identifier, e.g. "CHECK-0201"
#     TYPE       - "confirmed" or "needs_ai_review"
#     SEVERITY   - "BLOCKER", "MAJOR", or "MINOR"
#     DIMENSION  - Dimension number, e.g. "2"
#     DIM_NAME   - Dimension name, e.g. "SQL 注入防范"
#     TITLE      - Brief description of the finding
#     FILE       - File path where the issue was found
#     LINE       - Line number (can be empty or "null")
#     CODE       - Relevant code snippet (can be empty)
#     SUGGESTION - Suggested fix (can be empty)
#
# Output:
#   A single JSON object on one line, terminated by newline.
json_finding() {
    local id="${1:-}"
    local type="${2:-}"
    local severity="${3:-}"
    local dimension="${4:-}"
    local dim_name="${5:-}"
    local title="${6:-}"
    local file="${7:-}"
    local line="${8:-}"
    local code="${9:-}"
    local suggestion="${10:-}"

    # Escape all string values
    local esc_id esc_type esc_severity esc_dim_name esc_title esc_file esc_code esc_suggestion
    esc_id=$(json_escape "$id")
    esc_type=$(json_escape "$type")
    esc_severity=$(json_escape "$severity")
    esc_dim_name=$(json_escape "$dim_name")
    esc_title=$(json_escape "$title")
    esc_file=$(json_escape "$file")
    esc_code=$(json_escape "$code")
    esc_suggestion=$(json_escape "$suggestion")

    # Build line number: emit as JSON number if non-empty, otherwise null
    local line_json="null"
    if [[ -n "$line" && "$line" != "null" ]]; then
        line_json="$line"
    fi

    # Build code field: emit as string if non-empty, otherwise null
    local code_json="null"
    if [[ -n "$code" ]]; then
        code_json="\"${esc_code}\""
    fi

    # Build suggestion field: emit as string if non-empty, otherwise null
    local suggestion_json="null"
    if [[ -n "$suggestion" ]]; then
        suggestion_json="\"${esc_suggestion}\""
    fi

    printf '{"id":"%s","type":"%s","severity":"%s","dimension":%s,"dimensionName":"%s","title":"%s","file":"%s","line":%s,"code":%s,"suggestion":%s}\n' \
        "$esc_id" \
        "$esc_type" \
        "$esc_severity" \
        "$dimension" \
        "$esc_dim_name" \
        "$esc_title" \
        "$esc_file" \
        "$line_json" \
        "$code_json" \
        "$suggestion_json"
}

# json_finding_with_context ID TYPE SEVERITY DIMENSION DIM_NAME TITLE FILE CONTEXT_JSON
#   Output a finding with an arbitrary context object (for needs_ai_review findings).
#   The CONTEXT_JSON argument must be a valid JSON object string.
#
#   Arguments:
#     ID           - Check identifier, e.g. "CHECK-0601"
#     TYPE         - "confirmed" or "needs_ai_review"
#     SEVERITY     - "BLOCKER", "MAJOR", or "MINOR"
#     DIMENSION    - Dimension number
#     DIM_NAME     - Dimension name
#     TITLE        - Brief description of the finding
#     FILE         - File path where the issue was found
#     CONTEXT_JSON - A pre-formed JSON object with additional context
#
# Output:
#   A single JSON object on one line, terminated by newline.
json_finding_with_context() {
    local id="${1:-}"
    local type="${2:-}"
    local severity="${3:-}"
    local dimension="${4:-}"
    local dim_name="${5:-}"
    local title="${6:-}"
    local file="${7:-}"
    local context_json="${8:-{\}}"

    # Escape string values
    local esc_id esc_type esc_severity esc_dim_name esc_title esc_file
    esc_id=$(json_escape "$id")
    esc_type=$(json_escape "$type")
    esc_severity=$(json_escape "$severity")
    esc_dim_name=$(json_escape "$dim_name")
    esc_title=$(json_escape "$title")
    esc_file=$(json_escape "$file")

    # context_json is NOT escaped - it's already a valid JSON object
    printf '{"id":"%s","type":"%s","severity":"%s","dimension":%s,"dimensionName":"%s","title":"%s","file":"%s","context":%s}\n' \
        "$esc_id" \
        "$esc_type" \
        "$esc_severity" \
        "$dimension" \
        "$esc_dim_name" \
        "$esc_title" \
        "$esc_file" \
        "$context_json"
}

# ==============================================================================
# File Scanning Functions
#
# All find_* functions print one path per line to stdout.
# They accept a root directory as the first argument.
# ==============================================================================

# find_java_files DIR
#   Find all .java source files, excluding test/ directories.
find_java_files() {
    local dir="${1:-.}"
    find "$dir" -type f -name '*.java' \
        ! -path '*/test/*' \
        ! -path '*/tests/*' \
        ! -path '*/Test/*' \
        ! -path '*/__test__/*' \
        ! -path '*/androidTest/*' \
        2>/dev/null || true
}

# find_test_files DIR
#   Find all test .java files (files under test/ directories or named *Test.java).
find_test_files() {
    local dir="${1:-.}"
    # Find files under test directories, or files matching common test naming patterns
    {
        find "$dir" -type f -name '*.java' -path '*/test/*' 2>/dev/null || true
        find "$dir" -type f -name '*.java' -path '*/tests/*' 2>/dev/null || true
        find "$dir" -type f -name '*Test.java' 2>/dev/null || true
        find "$dir" -type f -name '*Tests.java' 2>/dev/null || true
        find "$dir" -type f -name '*IT.java' 2>/dev/null || true
        find "$dir" -type f -name '*Spec.java' 2>/dev/null || true
    } | sort -u
}

# find_xml_mappers DIR
#   Find MyBatis XML mapper files.
find_xml_mappers() {
    local dir="${1:-.}"
    find "$dir" -type f -name '*Mapper.xml' -o -name '*mapper.xml' -o -name '*Dao.xml' \
        2>/dev/null || true
}

# find_yaml_configs DIR
#   Find Spring application YAML configuration files.
find_yaml_configs() {
    local dir="${1:-.}"
    find "$dir" -type f \( -name 'application*.yml' -o -name 'application*.yaml' \
        -o -name 'bootstrap*.yml' -o -name 'bootstrap*.yaml' \) \
        ! -path '*/target/*' \
        ! -path '*/build/*' \
        2>/dev/null || true
}

# find_properties_configs DIR
#   Find Spring application properties configuration files.
find_properties_configs() {
    local dir="${1:-.}"
    find "$dir" -type f -name 'application*.properties' \
        ! -path '*/target/*' \
        ! -path '*/build/*' \
        2>/dev/null || true
}

# find_pom_files DIR
#   Find Maven pom.xml files.
find_pom_files() {
    local dir="${1:-.}"
    find "$dir" -type f -name 'pom.xml' \
        ! -path '*/target/*' \
        2>/dev/null || true
}

# find_gradle_files DIR
#   Find Gradle build files (build.gradle, build.gradle.kts, settings.gradle, etc.).
find_gradle_files() {
    local dir="${1:-.}"
    find "$dir" -type f \( -name 'build.gradle' -o -name 'build.gradle.kts' \
        -o -name 'settings.gradle' -o -name 'settings.gradle.kts' \) \
        ! -path '*/.gradle/*' \
        ! -path '*/build/*' \
        2>/dev/null || true
}

# ==============================================================================
# Text Processing Functions
# ==============================================================================

# count_lines FILE
#   Count lines in a file. Outputs the count to stdout.
#   Returns 0 if the file does not exist.
count_lines() {
    local file="${1:-}"
    if [[ -f "$file" ]]; then
        wc -l < "$file" | tr -d '[:space:]'
    else
        printf '0'
    fi
}

# extract_package DIR
#   Extract the base package name from Java source files in a directory.
#   Scans for `package` declarations and returns the most common root package.
#   Outputs the package name to stdout, or empty string if not found.
extract_package() {
    local dir="${1:-.}"
    # Find Java files and extract package declarations
    local packages
    packages=$(find "$dir" -type f -name '*.java' \
        ! -path '*/test/*' \
        ! -path '*/tests/*' \
        -exec grep -h '^package ' {} + 2>/dev/null \
        | sed 's/^package[[:space:]]*//; s/[[:space:]]*;.*//' \
        | sort | uniq -c | sort -rn \
        | head -1 \
        | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' || true)

    if [[ -z "$packages" ]]; then
        printf ''
        return
    fi

    # Try to find the shortest common package prefix
    # e.g., com.example.app.service -> com.example.app
    local base
    base=$(find "$dir" -type f -name '*.java' \
        ! -path '*/test/*' \
        ! -path '*/tests/*' \
        -exec grep -h '^package ' {} + 2>/dev/null \
        | sed 's/^package[[:space:]]*//; s/[[:space:]]*;.*//' \
        | sort -u \
        | awk -F. '
            NR == 1 { for (i = 1; i <= NF; i++) parts[i] = $i; n = NF; next }
            {
                for (i = 1; i <= n && i <= NF; i++) {
                    if ($i != parts[i]) { n = i - 1; break }
                }
                if (NF < n) n = NF
            }
            END {
                result = ""
                for (i = 1; i <= n; i++) {
                    if (i > 1) result = result "."
                    result = result parts[i]
                }
                print result
            }
        ' || true)

    # If we got a base package, use it; otherwise fall back to the most common one
    if [[ -n "$base" ]]; then
        printf '%s' "$base"
    else
        printf '%s' "$packages"
    fi
}

# is_controller FILE
#   Check if a Java file is a Spring Controller.
#   Returns 0 (true) if the file has @Controller or @RestController annotation.
#   Returns 1 (false) otherwise.
is_controller() {
    local file="${1:-}"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    grep -qE '@(Rest)?Controller' "$file" 2>/dev/null
}

# is_service FILE
#   Check if a Java file is a Spring Service.
#   Returns 0 (true) if the file has @Service annotation.
#   Returns 1 (false) otherwise.
is_service() {
    local file="${1:-}"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    grep -qE '@Service' "$file" 2>/dev/null
}

# ==============================================================================
# Utility / Logging Functions
#
# All log functions write to stderr so they never pollute the JSON output
# on stdout.
# ==============================================================================

# Log level color codes (used only if stderr is a terminal)
_LOG_COLOR_RESET=""
_LOG_COLOR_INFO=""
_LOG_COLOR_WARN=""
_LOG_COLOR_ERROR=""

if [[ -t 2 ]]; then
    _LOG_COLOR_RESET=$'\033[0m'
    _LOG_COLOR_INFO=$'\033[0;36m'   # cyan
    _LOG_COLOR_WARN=$'\033[0;33m'   # yellow
    _LOG_COLOR_ERROR=$'\033[0;31m'  # red
fi

# log_info MSG
#   Log an informational message to stderr.
log_info() {
    printf '%s[INFO]%s %s\n' "$_LOG_COLOR_INFO" "$_LOG_COLOR_RESET" "$*" >&2
}

# log_warn MSG
#   Log a warning message to stderr.
log_warn() {
    printf '%s[WARN]%s %s\n' "$_LOG_COLOR_WARN" "$_LOG_COLOR_RESET" "$*" >&2
}

# log_error MSG
#   Log an error message to stderr.
log_error() {
    printf '%s[ERROR]%s %s\n' "$_LOG_COLOR_ERROR" "$_LOG_COLOR_RESET" "$*" >&2
}

# check_dependency CMD
#   Check if a command-line tool is available on the PATH.
#   Logs a warning to stderr if it is not found.
#   Returns 0 if found, 1 if not.
check_dependency() {
    local cmd="${1:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_warn "Required dependency '$cmd' not found in PATH"
        return 1
    fi
    return 0
}
