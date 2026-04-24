#!/usr/bin/env bash
# ==============================================================================
# check-sql-injection.sh - SQL Injection Prevention checks
#
# Checks:
#   CHECK-0201 [BLOCKER] MyBatis using ${} instead of #{}
#   CHECK-0202 [BLOCKER] String concatenation to build SQL
#
# Provides: check_sql_injection PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding, find_xml_mappers, find_java_files
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _DIM_NUMBER=2
readonly _DIM_NAME="SQL 注入防范"

# ==============================================================================
# CHECK-0201: MyBatis ${} interpolation
# ==============================================================================

# _check_0201_xml_mappers PROJECT_PATH
#   Scan MyBatis XML mapper files for dangerous ${} interpolation.
#   Excludes occurrences inside XML comments (<!-- -->).
_check_0201_xml_mappers() {
    local project_path="$1"

    local mapper_files
    mapper_files=$(find_xml_mappers "$project_path")

    if [[ -z "$mapper_files" ]]; then
        return
    fi

    while IFS= read -r mapper_file; do
        [[ -z "$mapper_file" ]] && continue
        [[ ! -f "$mapper_file" ]] && continue

        local rel_path="${mapper_file#"$project_path"/}"

        # Strategy: strip XML comments, then grep for ${}
        # We use awk to remove comment blocks (handles multi-line comments)
        # then grep for ${...} patterns on the remaining lines.
        #
        # The awk script tracks original line numbers so we can report them.
        # Output format: "LINENUM:CONTENT"
        local hits
        hits=$(awk '
            BEGIN { in_comment = 0 }
            {
                line = $0
                lineno = NR
                # Process the line, removing comment sections
                result = ""
                while (length(line) > 0) {
                    if (in_comment) {
                        pos = index(line, "-->"  )
                        if (pos > 0) {
                            in_comment = 0
                            line = substr(line, pos + 3)
                        } else {
                            break
                        }
                    } else {
                        pos = index(line, "<!--")
                        if (pos > 0) {
                            result = result substr(line, 1, pos - 1)
                            line = substr(line, pos + 4)
                            in_comment = 1
                        } else {
                            result = result line
                            break
                        }
                    }
                }
                if (result ~ /\$\{/) {
                    print lineno ":" result
                }
            }
        ' "$mapper_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%:*}"
            local line_content="${hit#*:}"
            # Trim leading/trailing whitespace
            line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            json_finding \
                "CHECK-0201" \
                "confirmed" \
                "BLOCKER" \
                "$_DIM_NUMBER" \
                "$_DIM_NAME" \
                "MyBatis XML mapper uses \${} interpolation, vulnerable to SQL injection" \
                "$rel_path" \
                "$line_num" \
                "$line_content" \
                "Replace \${...} with #{...} for parameterized queries. If dynamic table/column names are truly needed, use a whitelist approach or MyBatis <choose>/<when> tags."
        done <<< "$hits"
    done <<< "$mapper_files"
}

# _check_0201_annotations PROJECT_PATH
#   Scan Java files for @Select/@Update/@Delete/@Insert annotations containing ${}.
#   Uses awk to track annotation blocks so multi-line annotations are handled
#   correctly without duplicate reports.
_check_0201_annotations() {
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

        # Use awk to track when we are inside a MyBatis SQL annotation and
        # report lines containing ${} within that context.
        # The awk script tracks open/close parentheses to determine the
        # annotation boundary, handling multi-line annotation values.
        # Output format: "LINENUM:CONTENT"
        local hits
        hits=$(awk '
            BEGIN { in_annotation = 0; paren_depth = 0 }
            {
                line = $0

                # Check if a new SQL annotation starts on this line
                if (!in_annotation && line ~ /@(Select|Update|Delete|Insert)/) {
                    in_annotation = 1
                    paren_depth = 0
                }

                if (in_annotation) {
                    # Count parentheses to track annotation boundaries
                    n = length(line)
                    for (i = 1; i <= n; i++) {
                        c = substr(line, i, 1)
                        if (c == "(") paren_depth++
                        if (c == ")") paren_depth--
                    }

                    # Check for ${} on this line
                    if (line ~ /\$\{/) {
                        # Trim leading whitespace for output
                        content = line
                        sub(/^[[:space:]]+/, "", content)
                        sub(/[[:space:]]+$/, "", content)
                        print NR ":" content
                    }

                    # Annotation ends when all parens are closed
                    if (paren_depth <= 0) {
                        in_annotation = 0
                        paren_depth = 0
                    }
                }
            }
        ' "$java_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%:*}"
            local line_content="${hit#*:}"

            json_finding \
                "CHECK-0201" \
                "confirmed" \
                "BLOCKER" \
                "$_DIM_NUMBER" \
                "$_DIM_NAME" \
                "MyBatis @SQL annotation uses \${} interpolation, vulnerable to SQL injection" \
                "$rel_path" \
                "$line_num" \
                "$line_content" \
                "Replace \${...} with #{...} in MyBatis annotations for parameterized queries. If dynamic identifiers are needed, use a whitelist or @SelectProvider with safe SQL building."
        done <<< "$hits"
    done <<< "$java_files"
}

# ==============================================================================
# CHECK-0202: String concatenation to build SQL
# ==============================================================================

# _check_0202_string_concat PROJECT_PATH
#   Scan Java files for SQL built via string concatenation.
_check_0202_string_concat() {
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

        # Pattern 1: String literals starting with SQL keywords followed by concatenation (+)
        # e.g., "SELECT " + foo, "INSERT INTO " + bar, "UPDATE " + x, "DELETE FROM " + y
        local hits
        hits=$(grep -n -E '"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[[:space:]]' "$java_file" 2>/dev/null) || true

        if [[ -n "$hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"

                # Check if this line has string concatenation via +
                if printf '%s' "$line_content" | grep -qE '"[^"]*"[[:space:]]*\+' 2>/dev/null; then
                    line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                    json_finding \
                        "CHECK-0202" \
                        "confirmed" \
                        "BLOCKER" \
                        "$_DIM_NUMBER" \
                        "$_DIM_NAME" \
                        "SQL built via string concatenation, vulnerable to SQL injection" \
                        "$rel_path" \
                        "$line_num" \
                        "$line_content" \
                        "Use parameterized queries (PreparedStatement with ?, or MyBatis #{}) instead of string concatenation. Never build SQL by concatenating user input."
                fi
            done <<< "$hits"
        fi

        # Pattern 2: String sql = "SELECT... concatenation
        # e.g., String sql = "SELECT * FROM " + tableName;
        local sql_var_hits
        sql_var_hits=$(grep -n -E 'String[[:space:]]+\w+[[:space:]]*=[[:space:]]*"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[[:space:]]' "$java_file" 2>/dev/null) || true

        if [[ -n "$sql_var_hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"

                # Only flag if there's concatenation (+ operator after a string)
                if printf '%s' "$line_content" | grep -qE '\+' 2>/dev/null; then
                    # Avoid double-reporting: check if already reported by Pattern 1
                    if printf '%s' "$line_content" | grep -qE '"[^"]*"[[:space:]]*\+' 2>/dev/null; then
                        continue  # Already caught by Pattern 1
                    fi

                    line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                    json_finding \
                        "CHECK-0202" \
                        "confirmed" \
                        "BLOCKER" \
                        "$_DIM_NUMBER" \
                        "$_DIM_NAME" \
                        "SQL built via string concatenation, vulnerable to SQL injection" \
                        "$rel_path" \
                        "$line_num" \
                        "$line_content" \
                        "Use parameterized queries (PreparedStatement with ?, or MyBatis #{}) instead of string concatenation. Never build SQL by concatenating user input."
                fi
            done <<< "$sql_var_hits"
        fi

        # Pattern 3: StringBuilder/StringBuffer with .append() containing SQL keywords
        # e.g., new StringBuilder("SELECT ").append(column)
        #        sb.append("SELECT * FROM ").append(tableName)
        local sb_hits
        sb_hits=$(grep -n -E '(StringBuilder|StringBuffer).*\.(append)\([[:space:]]*"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[[:space:]]' "$java_file" 2>/dev/null) || true

        if [[ -z "$sb_hits" ]]; then
            # Also try: new StringBuilder("SELECT ...
            sb_hits=$(grep -n -E 'new[[:space:]]+(StringBuilder|StringBuffer)[[:space:]]*\([[:space:]]*"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[[:space:]]' "$java_file" 2>/dev/null) || true
        fi

        if [[ -n "$sb_hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"
                line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0202" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_DIM_NUMBER" \
                    "$_DIM_NAME" \
                    "SQL built via StringBuilder/StringBuffer, vulnerable to SQL injection" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_content" \
                    "Use parameterized queries (PreparedStatement with ?, or MyBatis #{}) instead of building SQL with StringBuilder/StringBuffer. Consider using a query builder or ORM."
            done <<< "$sb_hits"
        fi
    done <<< "$java_files"
}

# ==============================================================================
# Public API
# ==============================================================================

# check_sql_injection PROJECT_PATH
#   Run all SQL injection prevention checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_sql_injection() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_sql_injection: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-0201: MyBatis \${} interpolation..."
    _check_0201_xml_mappers "$project_path"
    _check_0201_annotations "$project_path"

    log_info "Running CHECK-0202: SQL string concatenation..."
    _check_0202_string_concat "$project_path"

    log_info "SQL injection checks complete."
}
