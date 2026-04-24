#!/usr/bin/env bash
# ==============================================================================
# arch-review.sh - Java Server Architecture Review Tool
#
# Single entry-point script that orchestrates all check modules and outputs a
# complete JSON result to stdout.  All diagnostic / progress messages go to
# stderr so they never pollute the machine-readable output.
#
# Usage:
#   bash scripts/arch-review.sh --project /path/to/java-project [--mode MODE] [--dimensions DIMS]
#
# Modes: full (default), pr, focus, quick
#
# Compatibility: macOS, Linux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"

# ==============================================================================
# Source library files
# ==============================================================================
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/project-detector.sh"
source "$SCRIPT_DIR/lib/check-sql-injection.sh"
source "$SCRIPT_DIR/lib/check-hardcoded-secrets.sh"
source "$SCRIPT_DIR/lib/check-config.sh"
source "$SCRIPT_DIR/lib/check-logging.sh"
source "$SCRIPT_DIR/lib/check-error-handling.sh"
source "$SCRIPT_DIR/lib/check-code-layering.sh"
source "$SCRIPT_DIR/lib/check-dry.sh"
source "$SCRIPT_DIR/lib/check-api-validation.sh"
source "$SCRIPT_DIR/lib/check-testing.sh"
source "$SCRIPT_DIR/lib/check-data-storage.sh"
source "$SCRIPT_DIR/lib/check-db-migration.sh"

# ==============================================================================
# Constants
# ==============================================================================

# Dimensions that static shell scripts cannot fully cover:
#   0  - Coding standards (needs style/lint tools)
#   1  - Database index design (needs live DB or deep ORM analysis)
#   8  - Authentication & authorisation (needs semantic understanding)
#   9  - RESTful API design conventions (needs semantic understanding)
#   11 - Rate limiting / circuit-breaker (needs semantic understanding)
readonly UNCOVERED_DIMENSIONS="[0, 1, 8, 9, 11]"

# All available check functions in execution order
readonly ALL_CHECKS=(
    check_sql_injection
    check_hardcoded_secrets
    check_config
    check_logging
    check_error_handling
    check_code_layering
    check_dry
    check_api_validation
    check_testing
    check_data_storage
    check_db_migration
)

# ==============================================================================
# Defaults
# ==============================================================================
PROJECT_PATH=""
MODE="full"
DIMENSIONS=""

# ==============================================================================
# Usage / Help
# ==============================================================================
usage() {
    cat >&2 <<EOF
Java Server Architecture Review Tool v${VERSION}

Usage:
  bash $(basename "$0") --project PATH [--mode MODE] [--dimensions DIMS]

Arguments:
  --project PATH      (required) Path to the Java project to scan
  --mode MODE         Scan mode: full | pr | focus | quick  (default: full)
  --dimensions DIMS   Comma-separated dimension keywords (required for focus mode)
  --help              Show this help message
  --version           Show version

Modes:
  full    Run ALL check modules (default)
  pr      Detect changed files via git, only run relevant checks
  focus   Only run checks matching the specified dimension keywords
  quick   Run all checks but only include BLOCKER severity findings in output

Dimension keywords (for --mode focus):
  sql-injection   secrets         config          logging
  error-handling  layering        dry             api-validation
  testing         data-storage    db-migration
  security        (combo: sql-injection + secrets + api-validation)

Examples:
  bash $(basename "$0") --project /path/to/project --mode full
  bash $(basename "$0") --project /path/to/project --mode pr
  bash $(basename "$0") --project /path/to/project --mode focus --dimensions "sql-injection,security"
  bash $(basename "$0") --project /path/to/project --mode quick
EOF
    exit 0
}

# ==============================================================================
# Argument parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -lt 2 ]] && { log_error "--project requires a value"; exit 1; }
                PROJECT_PATH="$2"
                shift 2
                ;;
            --mode)
                [[ $# -lt 2 ]] && { log_error "--mode requires a value"; exit 1; }
                MODE="$2"
                shift 2
                ;;
            --dimensions)
                [[ $# -lt 2 ]] && { log_error "--dimensions requires a value"; exit 1; }
                DIMENSIONS="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            --version|-v)
                echo "$VERSION"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                echo >&2 "Run with --help for usage information."
                exit 1
                ;;
        esac
    done

    # --- Validate required arguments -----------------------------------------
    if [[ -z "$PROJECT_PATH" ]]; then
        log_error "--project PATH is required"
        echo >&2 "Run with --help for usage information."
        exit 1
    fi

    if [[ ! -d "$PROJECT_PATH" ]]; then
        log_error "Project path does not exist or is not a directory: $PROJECT_PATH"
        exit 1
    fi

    # Resolve to absolute path
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

    # --- Validate mode -------------------------------------------------------
    case "$MODE" in
        full|pr|focus|quick) ;;
        *)
            log_error "Invalid mode '$MODE'. Must be one of: full, pr, focus, quick"
            exit 1
            ;;
    esac

    # --- Validate dimensions for focus mode ----------------------------------
    if [[ "$MODE" == "focus" && -z "$DIMENSIONS" ]]; then
        log_error "--dimensions is required when using --mode focus"
        exit 1
    fi
}

# ==============================================================================
# Dimension keyword → check function(s) mapping
# ==============================================================================
resolve_checks_for_dimension() {
    local dim="$1"
    case "$dim" in
        sql-injection)   echo "check_sql_injection" ;;
        secrets)         echo "check_hardcoded_secrets" ;;
        config)          echo "check_config" ;;
        logging)         echo "check_logging" ;;
        error-handling)  echo "check_error_handling" ;;
        layering)        echo "check_code_layering" ;;
        dry)             echo "check_dry" ;;
        api-validation)  echo "check_api_validation" ;;
        testing)         echo "check_testing" ;;
        data-storage)    echo "check_data_storage" ;;
        db-migration)    echo "check_db_migration" ;;
        security)
            # Combo: three security-related checks
            echo "check_sql_injection"
            echo "check_hardcoded_secrets"
            echo "check_api_validation"
            ;;
        *)
            log_warn "Unknown dimension keyword: '$dim' — skipping"
            ;;
    esac
}

# ==============================================================================
# PR mode: determine relevant checks from changed files
# ==============================================================================
determine_pr_checks() {
    local project_path="$1"
    local changed_files=""

    # Strategy 1: diff against previous commit (post-merge / normal workflow)
    if git -C "$project_path" rev-parse HEAD~1 >/dev/null 2>&1; then
        changed_files=$(git -C "$project_path" diff --name-only HEAD~1 2>/dev/null || true)
    fi

    # Strategy 2: staged changes (pre-commit hook scenario)
    if [[ -z "$changed_files" ]]; then
        changed_files=$(git -C "$project_path" diff --cached --name-only 2>/dev/null || true)
    fi

    if [[ -z "$changed_files" ]]; then
        log_warn "PR mode: no changed files detected — falling back to full scan"
        printf '%s\n' "${ALL_CHECKS[@]}"
        return
    fi

    log_info "PR mode: changed files:"
    while IFS= read -r f; do
        [[ -n "$f" ]] && log_info "  $f"
    done <<< "$changed_files"

    # Classify changed file types
    local has_xml_mapper=false
    local has_java=false
    local has_config=false
    local has_build=false

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        case "$file" in
            *Mapper.xml|*mapper.xml|*Dao.xml)
                has_xml_mapper=true ;;
            *.java)
                has_java=true ;;
            *.yml|*.yaml|*.properties)
                has_config=true ;;
            pom.xml|*/pom.xml|build.gradle|*/build.gradle|build.gradle.kts|*/build.gradle.kts)
                has_build=true ;;
        esac
    done <<< "$changed_files"

    # Collect relevant checks (may contain duplicates)
    local -a checks=()

    if [[ "$has_xml_mapper" == true ]]; then
        checks+=(check_sql_injection check_data_storage)
    fi

    if [[ "$has_java" == true ]]; then
        checks+=(
            check_sql_injection
            check_hardcoded_secrets
            check_config
            check_logging
            check_error_handling
            check_code_layering
            check_dry
            check_api_validation
            check_data_storage
        )
    fi

    if [[ "$has_config" == true ]]; then
        checks+=(check_config check_error_handling check_hardcoded_secrets)
    fi

    if [[ "$has_build" == true ]]; then
        checks+=(check_testing check_db_migration)
    fi

    if [[ ${#checks[@]} -eq 0 ]]; then
        log_warn "PR mode: no checks match the changed file types — running full scan"
        printf '%s\n' "${ALL_CHECKS[@]}"
    else
        # Deduplicate while preserving a stable order
        printf '%s\n' "${checks[@]}" | awk '!seen[$0]++'
    fi
}

# ==============================================================================
# Count scannable files in the project
# ==============================================================================
count_files_scanned() {
    local project_path="$1"

    # Gather all file lists, deduplicate, and count
    local count
    count=$(
        {
            find_java_files "$project_path"
            find_xml_mappers "$project_path"
            find_yaml_configs "$project_path"
            find_properties_configs "$project_path"
            find_pom_files "$project_path"
            find_gradle_files "$project_path"
        } | sort -u | wc -l | tr -d '[:space:]'
    )
    echo "$count"
}

# ==============================================================================
# Run check modules and collect findings into a temp file
# ==============================================================================
run_checks() {
    local project_path="$1"
    shift
    local -a checks=("$@")

    local findings_file
    findings_file=$(mktemp "${TMPDIR:-/tmp}/arch-review-findings.XXXXXX")

    for check_fn in "${checks[@]}"; do
        [[ -z "$check_fn" ]] && continue
        log_info "Running: ${check_fn} ..."

        # stdout → findings (appended to temp file)
        # stderr → pass through to caller's stderr (progress / log messages)
        if ! "$check_fn" "$project_path" >> "$findings_file" 2>&2; then
            log_warn "${check_fn} exited with non-zero status — continuing"
        fi
    done

    # Return the path to the findings file
    echo "$findings_file"
}

# ==============================================================================
# Assemble the final JSON output
# ==============================================================================
assemble_output() {
    local mode="$1"
    local dimensions_label="$2"
    local findings_file="$3"
    local project_json="$4"
    local files_scanned="$5"
    local start_time="$6"

    # --- Timing --------------------------------------------------------------
    local end_time
    end_time=$(date +%s)
    local duration_secs=$(( end_time - start_time ))
    local duration="${duration_secs}s"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # --- Count findings by severity and type ---------------------------------
    local total=0 blocker=0 major=0 minor=0 confirmed=0 needs_ai_review=0

    if [[ -s "$findings_file" ]]; then
        total=$(wc -l < "$findings_file" | tr -d '[:space:]')
        blocker=$(grep -c '"severity":"BLOCKER"' "$findings_file" 2>/dev/null || true)
        major=$(grep -c '"severity":"MAJOR"' "$findings_file" 2>/dev/null || true)
        minor=$(grep -c '"severity":"MINOR"' "$findings_file" 2>/dev/null || true)
        confirmed=$(grep -c '"type":"confirmed"' "$findings_file" 2>/dev/null || true)
        needs_ai_review=$(grep -c '"type":"needs_ai_review"' "$findings_file" 2>/dev/null || true)
    fi

    # --- Build the findings JSON array ---------------------------------------
    # In quick mode only BLOCKER findings are included in the output array.
    local findings_json="["
    local first=true

    if [[ -s "$findings_file" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            if [[ "$mode" == "quick" ]]; then
                # shellcheck disable=SC2254
                case "$line" in
                    *'"severity":"BLOCKER"'*) ;;  # keep it
                    *) continue ;;                # skip non-BLOCKER
                esac
            fi

            if [[ "$first" == true ]]; then
                first=false
            else
                findings_json+=","
            fi
            findings_json+="$line"
        done < "$findings_file"
    fi
    findings_json+="]"

    # --- Build the dimensions label array ------------------------------------
    local dims_json
    case "$mode" in
        focus)
            dims_json="["
            local first_dim=true
            IFS=',' read -ra dim_arr <<< "$dimensions_label"
            for d in "${dim_arr[@]}"; do
                # Trim whitespace
                d="${d#"${d%%[![:space:]]*}"}"
                d="${d%"${d##*[![:space:]]}"}"
                if [[ "$first_dim" == true ]]; then
                    first_dim=false
                else
                    dims_json+=","
                fi
                dims_json+="\"$d\""
            done
            dims_json+="]"
            ;;
        pr)
            dims_json='["pr-changed"]'
            ;;
        *)
            dims_json='["all"]'
            ;;
    esac

    # --- Emit the final JSON object ------------------------------------------
    cat <<FINAL_JSON
{
  "version": "${VERSION}",
  "timestamp": "${timestamp}",
  "project": ${project_json},
  "scan": {
    "mode": "${mode}",
    "dimensions": ${dims_json},
    "filesScanned": ${files_scanned},
    "duration": "${duration}"
  },
  "findings": ${findings_json},
  "summary": {
    "total": ${total},
    "blocker": ${blocker},
    "major": ${major},
    "minor": ${minor},
    "confirmed": ${confirmed},
    "needsAiReview": ${needs_ai_review},
    "healthScore": null
  },
  "uncoveredDimensions": ${UNCOVERED_DIMENSIONS}
}
FINAL_JSON
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    parse_args "$@"

    local start_time
    start_time=$(date +%s)

    log_info "========================================"
    log_info "Java Server Architecture Review v${VERSION}"
    log_info "Project : $PROJECT_PATH"
    log_info "Mode    : $MODE"
    [[ -n "$DIMENSIONS" ]] && log_info "Dimensions: $DIMENSIONS"
    log_info "========================================"

    # Step 1 — Detect project metadata
    log_info "Detecting project structure..."
    local project_json
    project_json=$(detect_project "$PROJECT_PATH")

    # Step 2 — Determine which checks to run
    local -a checks_to_run=()
    local dimensions_label=""

    case "$MODE" in
        full|quick)
            checks_to_run=("${ALL_CHECKS[@]}")
            dimensions_label="all"
            ;;
        pr)
            dimensions_label="pr-changed"
            local pr_checks
            pr_checks=$(determine_pr_checks "$PROJECT_PATH")
            while IFS= read -r fn; do
                [[ -n "$fn" ]] && checks_to_run+=("$fn")
            done <<< "$pr_checks"
            ;;
        focus)
            dimensions_label="$DIMENSIONS"
            local raw_focus_checks=""
            IFS=',' read -ra dim_arr <<< "$DIMENSIONS"
            for dim in "${dim_arr[@]}"; do
                # Trim whitespace
                dim="${dim#"${dim%%[![:space:]]*}"}"
                dim="${dim%"${dim##*[![:space:]]}"}"
                local resolved
                resolved=$(resolve_checks_for_dimension "$dim")
                [[ -n "$resolved" ]] && raw_focus_checks+="${resolved}"$'\n'
            done
            # Deduplicate
            while IFS= read -r fn; do
                [[ -n "$fn" ]] && checks_to_run+=("$fn")
            done <<< "$(echo "$raw_focus_checks" | awk 'NF && !seen[$0]++')"
            ;;
    esac

    if [[ ${#checks_to_run[@]} -eq 0 ]]; then
        log_error "No checks to run — verify your --dimensions keywords"
        exit 1
    fi

    log_info "Checks to run (${#checks_to_run[@]}): ${checks_to_run[*]}"

    # Step 3 — Count scannable files
    local files_scanned
    files_scanned=$(count_files_scanned "$PROJECT_PATH")
    log_info "Scannable files: ${files_scanned}"

    # Step 4 — Execute checks
    local findings_file
    findings_file=$(run_checks "$PROJECT_PATH" "${checks_to_run[@]}")

    local finding_count=0
    [[ -s "$findings_file" ]] && finding_count=$(wc -l < "$findings_file" | tr -d '[:space:]')
    log_info "Total findings collected: ${finding_count}"

    # Step 5 — Assemble and emit the final JSON to stdout
    assemble_output \
        "$MODE" \
        "$dimensions_label" \
        "$findings_file" \
        "$project_json" \
        "$files_scanned" \
        "$start_time"

    # Cleanup temp file
    rm -f "$findings_file"

    log_info "Review complete."
}

main "$@"
