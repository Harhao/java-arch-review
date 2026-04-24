#!/usr/bin/env bash
# ==============================================================================
# check-dry.sh - DRY Principle violation checks
#
# Checks:
#   CHECK-0701 [MAJOR] Magic numbers/strings (confirmed / needs_ai_review)
#   CHECK-0702 [MAJOR] Duplicate code patterns (needs_ai_review)
#
# Provides: check_dry PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding, json_finding_with_context,
#           find_java_files, count_lines
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _DRY_DIM_NUMBER=7
readonly _DRY_DIM_NAME="DRY 原则"

# ==============================================================================
# CHECK-0701: Magic numbers and strings
# ==============================================================================

# _check_0701_magic_numbers PROJECT_PATH
#   Scan Java source files for magic numeric literals in conditions and
#   switch cases. Excludes common acceptable values, constant declarations,
#   and array index accesses.
_check_0701_magic_numbers() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        local rel_path="${java_file#"$project_path"/}"

        # Use awk to detect magic numbers in conditions and switch cases.
        # Rules:
        #   - Skip lines with "static final" (constant declarations)
        #   - Skip single-line comments and common annotations
        #   - Match: if/else-if conditions with == != > < >= <= comparisons to numeric literals
        #   - Match: case <number>:
        #   - Exclude common acceptable values: 0, 1, -1, 2, 10, 100, 1000
        #   - Exclude array index patterns like [0] [1]
        local hits
        hits=$(awk '
        /static[[:space:]]+final/ { next }
        /^[[:space:]]*\/\// { next }
        /^[[:space:]]*\*/ { next }
        /^[[:space:]]*\/\*/ { next }
        {
            line = $0

            # Check for conditions: if (...== 123), if (xxx > 100), etc.
            # Pattern: comparison operators followed/preceded by numeric literals
            if (line ~ /if[[:space:]]*\(/ || line ~ /else[[:space:]]+if[[:space:]]*\(/) {
                # Extract numeric literals from condition comparisons
                # Match patterns like: == 42, != 99, > 50, < 200, >= 30, <= 500
                temp = line
                while (match(temp, /(==|!=|>=|<=|>|<)[[:space:]]*-?[0-9]+/, arr) || \
                       match(temp, /-?[0-9]+[[:space:]]*(==|!=|>=|<=|>|<)/, arr)) {
                    # Extract the numeric value
                    matched = substr(temp, RSTART, RLENGTH)
                    # Pull out just the number
                    gsub(/[^0-9-]/, " ", matched)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", matched)
                    split(matched, nums, /[[:space:]]+/)
                    for (i in nums) {
                        n = nums[i]
                        if (n != "" && n != "0" && n != "1" && n != "-1" && \
                            n != "2" && n != "10" && n != "100" && n != "1000") {
                            print NR ":" line
                            temp = ""
                            break
                        }
                    }
                    if (temp == "") break
                    temp = substr(temp, RSTART + RLENGTH)
                }
                next
            }

            # Check for switch case with magic number: case 42:
            if (match(line, /case[[:space:]]+-?[0-9]+[[:space:]]*:/)) {
                matched = substr(line, RSTART, RLENGTH)
                gsub(/[^0-9-]/, "", matched)
                if (matched != "0" && matched != "1" && matched != "-1" && \
                    matched != "2" && matched != "10" && matched != "100" && matched != "1000") {
                    print NR ":" line
                }
            }
        }
        ' "$java_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        # Deduplicate by line number (awk may emit a line twice from both branches)
        hits=$(printf '%s\n' "$hits" | sort -t: -k1,1n -u)

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%:*}"
            local line_content="${hit#*:}"
            line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            json_finding \
                "CHECK-0701" \
                "confirmed" \
                "MAJOR" \
                "$_DRY_DIM_NUMBER" \
                "$_DRY_DIM_NAME" \
                "Magic number in condition or switch case — extract to a named constant" \
                "$rel_path" \
                "$line_num" \
                "$line_content" \
                "Extract the numeric literal into a descriptive static final constant (e.g. private static final int MAX_RETRY_COUNT = 3;)."
        done <<< "$hits"
    done <<< "$java_files"
}

# _check_0701_repeated_strings PROJECT_PATH
#   Detect string literals that appear 3 or more times across different files.
#   Only considers non-trivial strings (length >= 6, not pure whitespace, not
#   common framework strings).
_check_0701_repeated_strings() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    # Phase 1: Collect all string literals with their file paths.
    # Output format: FILE_PATH<TAB>STRING_VALUE
    # We use grep to extract quoted strings, then awk to filter and tabulate.
    local tmp_strings
    tmp_strings=$(mktemp "${TMPDIR:-/tmp}/dry_strings.XXXXXX") || return

    # Trap to clean up temp file
    trap 'rm -f "${tmp_strings:-}"' RETURN

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        local rel_path="${java_file#"$project_path"/}"

        # Extract string literals from each file.
        # - Skip lines that are constant declarations (static final) since those ARE the fix
        # - Skip import/package lines
        # - Skip single-line comments
        grep -n '"[^"]*"' "$java_file" 2>/dev/null \
            | grep -v 'static[[:space:]]*final' \
            | grep -v '^\s*//' \
            | grep -v '^[[:space:]]*\*' \
            | grep -v '^[0-9]*:[[:space:]]*import ' \
            | grep -v '^[0-9]*:[[:space:]]*package ' \
            | sed -n 's/.*"\([^"]*\)".*/\1/p' \
            | while IFS= read -r str_val; do
                # Filter: minimum length 6, not whitespace-only, not empty
                if [[ ${#str_val} -ge 6 ]] && [[ "$str_val" =~ [^[:space:]] ]]; then
                    # Skip very common framework strings that are usually acceptable
                    case "$str_val" in
                        "application/json"|"text/html"|"text/plain"|"utf-8"|"UTF-8"|\
                        "Content-Type"|"Authorization"|"Accept"|"GET"|"POST"|"PUT"|"DELETE"|\
                        "classpath:"|"classpath*:"|"yyyy-MM-dd"|"yyyy-MM-dd HH:mm:ss"|\
                        "HH:mm:ss"|"success"|"failed"|"error"|"message"|"result")
                            continue
                            ;;
                    esac
                    printf '%s\t%s\n' "$rel_path" "$str_val"
                fi
            done >> "$tmp_strings"
    done <<< "$java_files"

    if [[ ! -s "$tmp_strings" ]]; then
        return
    fi

    # Phase 2: Find strings that appear in 3+ different files.
    # Group by string value, count distinct files.
    local repeated
    repeated=$(awk -F'\t' '
    {
        str = $2
        file = $1
        if (!(str SUBSEP file in seen)) {
            seen[str, file] = 1
            file_count[str]++
            if (!(str in files)) {
                files[str] = file
            } else {
                files[str] = files[str] ", " file
            }
        }
    }
    END {
        for (str in file_count) {
            if (file_count[str] >= 3) {
                print file_count[str] "\t" str "\t" files[str]
            }
        }
    }
    ' "$tmp_strings" | sort -t$'\t' -k1,1rn) || true

    if [[ -z "$repeated" ]]; then
        return
    fi

    while IFS=$'\t' read -r count str_val file_list; do
        [[ -z "$str_val" ]] && continue

        # Truncate file list if too long for readability
        local display_files="$file_list"
        if [[ ${#display_files} -gt 200 ]]; then
            display_files="${display_files:0:200}..."
        fi

        local context
        context=$(printf '{"repeatedString":"%s","occurrenceFileCount":%s,"files":"%s"}' \
            "$(json_escape "$str_val")" \
            "$count" \
            "$(json_escape "$display_files")")

        json_finding_with_context \
            "CHECK-0701" \
            "needs_ai_review" \
            "MAJOR" \
            "$_DRY_DIM_NUMBER" \
            "$_DRY_DIM_NAME" \
            "String literal \"${str_val}\" repeated in ${count} files — consider extracting to a constant" \
            "(multiple files)" \
            "$context"
    done <<< "$repeated"

    rm -f "${tmp_strings:-}"
    trap - RETURN
}

# ==============================================================================
# CHECK-0702: Duplicate code patterns
# ==============================================================================

# _check_0702_similar_files PROJECT_PATH
#   Detect pairs of files that may contain duplicated logic by heuristic:
#   - Same class name pattern (e.g. XxxServiceImpl, XxxServiceImpl)
#   - Similar line counts (within +/- 10%)
_check_0702_similar_files() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    # Collect file info: relative path, line count, class name suffix pattern
    local tmp_file_info
    tmp_file_info=$(mktemp "${TMPDIR:-/tmp}/dry_fileinfo.XXXXXX") || return
    trap 'rm -f "${tmp_file_info:-}"' RETURN

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        local rel_path="${java_file#"$project_path"/}"
        local basename
        basename=$(basename "$java_file" .java)
        local lines
        lines=$(count_lines "$java_file")

        # Extract a suffix pattern: the last "word" in CamelCase
        # e.g. UserServiceImpl -> ServiceImpl, OrderController -> Controller
        local suffix=""
        if [[ "$basename" =~ (ServiceImpl|Service|Controller|Repository|Dao|Handler|Manager|Helper|Util|Utils|Converter|Mapper|Adapter|Listener|Provider|Factory|Strategy|Processor)$ ]]; then
            suffix="${BASH_REMATCH[1]}"
        fi

        # Only consider files with a recognized pattern and reasonable size
        if [[ -n "$suffix" && "$lines" -gt 30 ]]; then
            printf '%s\t%s\t%s\t%s\n' "$rel_path" "$lines" "$suffix" "$basename" >> "$tmp_file_info"
        fi
    done <<< "$java_files"

    if [[ ! -s "$tmp_file_info" ]]; then
        return
    fi

    # Compare files with the same suffix pattern for similar line counts.
    # Use awk to find pairs within the same suffix group.
    local pairs
    pairs=$(awk -F'\t' '
    {
        path[NR]  = $1
        lines[NR] = $2 + 0
        suffix[NR] = $3
        name[NR]   = $4
        count = NR
    }
    END {
        for (i = 1; i <= count; i++) {
            for (j = i + 1; j <= count; j++) {
                if (suffix[i] != suffix[j]) continue
                if (path[i] == path[j]) continue

                # Check line count similarity: within +/- 10%
                bigger  = (lines[i] > lines[j]) ? lines[i] : lines[j]
                smaller = (lines[i] > lines[j]) ? lines[j] : lines[i]
                if (bigger == 0) continue
                ratio = smaller / bigger

                if (ratio >= 0.9) {
                    print path[i] "\t" lines[i] "\t" path[j] "\t" lines[j] "\t" suffix[i]
                }
            }
        }
    }
    ' "$tmp_file_info") || true

    if [[ -z "$pairs" ]]; then
        return
    fi

    while IFS=$'\t' read -r file_a lines_a file_b lines_b suffix; do
        [[ -z "$file_a" ]] && continue

        local context
        context=$(printf '{"fileA":"%s","linesA":%s,"fileB":"%s","linesB":%s,"commonSuffix":"%s"}' \
            "$(json_escape "$file_a")" \
            "$lines_a" \
            "$(json_escape "$file_b")" \
            "$lines_b" \
            "$(json_escape "$suffix")")

        json_finding_with_context \
            "CHECK-0702" \
            "needs_ai_review" \
            "MAJOR" \
            "$_DRY_DIM_NUMBER" \
            "$_DRY_DIM_NAME" \
            "Possible duplicate code: ${file_a} (${lines_a}L) and ${file_b} (${lines_b}L) share ${suffix} pattern with similar size" \
            "$file_a" \
            "$context"
    done <<< "$pairs"

    rm -f "${tmp_file_info:-}"
    trap - RETURN
}

# _check_0702_long_methods PROJECT_PATH
#   Detect methods longer than 80 lines, which often indicate code that
#   could be extracted and reused.
_check_0702_long_methods() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        local rel_path="${java_file#"$project_path"/}"

        # Use awk to find method boundaries and measure their length.
        # Heuristic: a method starts with a line matching typical Java method
        # signatures (access modifier / annotation, return type, name, parens)
        # followed by an opening brace. We track brace depth to find the end.
        local hits
        hits=$(awk '
        BEGIN {
            in_method    = 0
            brace_depth  = 0
            method_start = 0
            method_name  = ""
        }

        # Detect method signature: looks for lines like
        #   public void foo(...) {
        #   private static List<String> bar(int x) {
        #   protected ResponseEntity<?> baz(
        # We require at least an access modifier or a return type + name + parens.
        !in_method && /^[[:space:]]*(public|private|protected|static|final|synchronized|abstract|native|default)[[:space:]]/ \
            && /[a-zA-Z_][a-zA-Z0-9_<>,\[\] \t]*[[:space:]+][a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/ \
            && !/^[[:space:]]*(class|interface|enum|import|package|return)[[:space:]]/ {

            # Try to grab method name
            temp = $0
            gsub(/\(.*/, "", temp)       # remove from ( onward
            gsub(/.*[[:space:]]/, "", temp) # keep last word
            candidate_name = temp
            candidate_start = NR

            # Check if opening brace is on this line
            if ($0 ~ /\{/) {
                in_method    = 1
                brace_depth  = 0
                method_start = candidate_start
                method_name  = candidate_name

                # Count braces on this line
                line = $0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1)
                    if (c == "{") brace_depth++
                    if (c == "}") brace_depth--
                }
                if (brace_depth <= 0) {
                    # Single-line method, skip
                    in_method = 0
                }
                next
            }
            # If no brace yet, wait for next lines
            candidate_pending = 1
            next
        }

        # If we had a method signature without brace, look for the opening brace
        candidate_pending && /\{/ {
            in_method    = 1
            brace_depth  = 0
            method_start = candidate_start
            method_name  = candidate_name
            candidate_pending = 0

            line = $0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "{") brace_depth++
                if (c == "}") brace_depth--
            }
            if (brace_depth <= 0) {
                in_method = 0
            }
            next
        }

        # Cancel pending if we hit a non-brace line
        candidate_pending && !/^[[:space:]]*$/ && !/\{/ {
            candidate_pending = 0
        }

        # Inside a method: track brace depth
        in_method {
            line = $0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "{") brace_depth++
                if (c == "}") brace_depth--
            }

            if (brace_depth <= 0) {
                method_length = NR - method_start
                if (method_length > 80) {
                    print method_start ":" method_length ":" method_name
                }
                in_method = 0
            }
        }
        ' "$java_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num length method_name
            line_num=$(printf '%s' "$hit" | cut -d: -f1)
            length=$(printf '%s' "$hit" | cut -d: -f2)
            method_name=$(printf '%s' "$hit" | cut -d: -f3-)

            local context
            context=$(printf '{"methodName":"%s","startLine":%s,"lineCount":%s}' \
                "$(json_escape "$method_name")" \
                "$line_num" \
                "$length")

            json_finding_with_context \
                "CHECK-0702" \
                "needs_ai_review" \
                "MAJOR" \
                "$_DRY_DIM_NUMBER" \
                "$_DRY_DIM_NAME" \
                "Method '${method_name}' is ${length} lines long (>${_DRY_MAX_METHOD_LINES:-80}) — likely contains extractable duplicate logic" \
                "$rel_path" \
                "$context"
        done <<< "$hits"
    done <<< "$java_files"
}

# ==============================================================================
# Public API
# ==============================================================================

# check_dry PROJECT_PATH
#   Run all DRY principle violation checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_dry() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_dry: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-0701: Magic numbers in conditions/switch cases..."
    _check_0701_magic_numbers "$project_path"

    log_info "Running CHECK-0701: Repeated string literals across files..."
    _check_0701_repeated_strings "$project_path"

    log_info "Running CHECK-0702: Suspiciously similar files..."
    _check_0702_similar_files "$project_path"

    log_info "Running CHECK-0702: Very long methods..."
    _check_0702_long_methods "$project_path"

    log_info "DRY principle checks complete."
}
