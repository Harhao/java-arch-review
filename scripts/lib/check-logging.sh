#!/usr/bin/env bash
# ==============================================================================
# check-logging.sh - Logging Standards (CHECK-0401 ~ CHECK-0404)
#
# Validates logging practices in Java/Spring Boot projects:
#   CHECK-0401 [BLOCKER] Critical operations missing logs
#   CHECK-0402 [BLOCKER] Exception caught without logging
#   CHECK-0403 [MAJOR]   Logs missing context
#   CHECK-0404 [MAJOR]   Incorrect log levels
#
# Provides: check_logging PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension metadata
_LOG_DIMENSION=4
_LOG_DIM_NAME="日志规范"

###############################################################################
# Public API
###############################################################################

# check_logging PROJECT_PATH
#   Run all logging checks against the given project directory.
check_logging() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_logging: invalid project path: $1"
        return 1
    }

    log_info "Running logging checks on: $project_path"

    _check_0401_critical_ops_missing_logs "$project_path"
    _check_0402_catch_without_logging "$project_path"
    _check_0403_logs_missing_context "$project_path"
    _check_0404_incorrect_log_levels "$project_path"

    log_info "Logging checks complete."
}

###############################################################################
# CHECK-0401 [BLOCKER] Critical operations missing logs (needs_ai_review)
#
# Service/Controller methods that perform write operations (save/update/delete/
# insert) but contain NO log statements (log./logger./LOG.).
###############################################################################
_check_0401_critical_ops_missing_logs() {
    local project_path="$1"

    log_info "CHECK-0401: Scanning for critical operations missing logs..."

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0401: No Java source files found, skipping."
        return
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only check Service and Controller classes
        if ! is_service "$file" && ! is_controller "$file"; then
            continue
        fi

        local rel_path="${file#"$project_path"/}"

        # Use awk to find methods with write-operation calls but no log statements.
        # Strategy: track brace depth to identify method boundaries, look for
        # DAO write calls and log references within each method.
        awk '
        BEGIN {
            depth = 0
            in_method = 0
            method_name = ""
            method_line = 0
            has_write_op = 0
            has_log = 0
        }

        # Detect method declarations (simplified: visibility + return-type + name + parens)
        /^[[:space:]]*(public|protected|private)[[:space:]].*\(/ && !/^[[:space:]]*(class|interface|enum|import)/ {
            # Extract method name
            line = $0
            gsub(/\(.*/, "", line)
            n = split(line, parts, /[[:space:]]+/)
            if (n >= 1) {
                candidate = parts[n]
                # Skip annotations and common non-method patterns
                if (candidate !~ /^@/ && candidate !~ /^(class|interface|enum)$/) {
                    if (in_method && has_write_op && !has_log) {
                        print method_line ":" method_name
                    }
                    in_method = 1
                    method_name = candidate
                    method_line = NR
                    has_write_op = 0
                    has_log = 0
                    depth = 0
                }
            }
        }

        # Track write operations (DAO calls)
        in_method && /\.(save|update|delete|insert|remove|add|create|persist|merge|batchInsert|batchUpdate|batchDelete|saveOrUpdate|deleteById|updateById)\s*\(/ {
            has_write_op = 1
        }

        # Track log statements
        in_method && /(log|logger|LOG)\.(trace|debug|info|warn|error|fatal)\s*\(/ {
            has_log = 1
        }

        # Track brace depth to know when a method ends
        in_method {
            n = gsub(/{/, "{")
            c = gsub(/}/, "}")
            depth += n - c
            if (depth <= 0 && method_line != NR) {
                if (has_write_op && !has_log) {
                    print method_line ":" method_name
                }
                in_method = 0
                method_name = ""
                has_write_op = 0
                has_log = 0
            }
        }

        END {
            if (in_method && has_write_op && !has_log) {
                print method_line ":" method_name
            }
        }
        ' "$file" | while IFS=: read -r line_num method; do
            [[ -z "$line_num" ]] && continue
            local ctx
            ctx=$(printf '{"methodName":"%s","file":"%s","line":%s,"reason":"Method performs write operation (save/update/delete/insert) but has no log statement"}' \
                "$(json_escape "$method")" \
                "$(json_escape "$rel_path")" \
                "$line_num")

            json_finding_with_context \
                "CHECK-0401" \
                "needs_ai_review" \
                "BLOCKER" \
                "$_LOG_DIMENSION" \
                "$_LOG_DIM_NAME" \
                "关键操作缺少日志: 方法 ${method}() 执行写操作但未记录日志" \
                "$rel_path" \
                "$ctx"
        done

    done <<< "$java_files"
}

###############################################################################
# CHECK-0402 [BLOCKER] Exception caught without logging
#
# Find catch blocks that:
#   a) contain e.printStackTrace() → confirmed (should use logger)
#   b) contain no log/logger/LOG statement → needs_ai_review
###############################################################################
_check_0402_catch_without_logging() {
    local project_path="$1"

    log_info "CHECK-0402: Scanning for catch blocks without logging..."

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0402: No Java source files found, skipping."
        return
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local rel_path="${file#"$project_path"/}"

        # Use awk to parse catch blocks and check for log statements.
        # Track brace depth from the opening { of each catch block.
        awk '
        BEGIN {
            in_catch = 0
            catch_depth = 0
            catch_line = 0
            has_log = 0
            has_print_stack = 0
            catch_header = ""
        }

        # Detect catch block start
        /catch[[:space:]]*\(/ {
            # If we were already in a catch, emit the previous one
            if (in_catch) {
                if (has_print_stack) {
                    print catch_line ":printStackTrace:" catch_header
                } else if (!has_log) {
                    print catch_line ":noLog:" catch_header
                }
            }

            in_catch = 0
            catch_depth = 0
            has_log = 0
            has_print_stack = 0
            catch_line = NR

            # Extract the catch header for context
            header = $0
            gsub(/^[[:space:]]+/, "", header)
            gsub(/[[:space:]]+$/, "", header)
            catch_header = header
        }

        # After seeing catch(, look for the opening brace to start tracking
        /catch[[:space:]]*\(/ {
            # Count braces on this same line
            line = $0
            n = gsub(/{/, "{", line)
            c = gsub(/}/, "}", line)
            if (n > 0) {
                in_catch = 1
                catch_depth = n - c
            }
            next
        }

        # If we saw catch but havent found opening brace yet
        !in_catch && catch_line > 0 && /{/ {
            in_catch = 1
            line = $0
            n = gsub(/{/, "{", line)
            c = gsub(/}/, "}", line)
            catch_depth = n - c
            next
        }

        in_catch {
            # Check for log statements
            if ($0 ~ /(log|logger|LOG)\.(trace|debug|info|warn|error|fatal)[[:space:]]*\(/) {
                has_log = 1
            }

            # Check for printStackTrace
            if ($0 ~ /\.printStackTrace[[:space:]]*\(/) {
                has_print_stack = 1
            }

            # Track brace depth
            line = $0
            n = gsub(/{/, "{", line)
            c = gsub(/}/, "}", line)
            catch_depth += n - c

            # Catch block ended
            if (catch_depth <= 0) {
                if (has_print_stack) {
                    print catch_line ":printStackTrace:" catch_header
                } else if (!has_log) {
                    print catch_line ":noLog:" catch_header
                }
                in_catch = 0
                catch_line = 0
                has_log = 0
                has_print_stack = 0
                catch_header = ""
            }
        }

        END {
            if (in_catch) {
                if (has_print_stack) {
                    print catch_line ":printStackTrace:" catch_header
                } else if (!has_log) {
                    print catch_line ":noLog:" catch_header
                }
            }
        }
        ' "$file" | while IFS=: read -r line_num issue_type catch_info; do
            [[ -z "$line_num" ]] && continue

            if [[ "$issue_type" == "printStackTrace" ]]; then
                json_finding \
                    "CHECK-0402" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_LOG_DIMENSION" \
                    "$_LOG_DIM_NAME" \
                    "异常捕获使用 printStackTrace() 而非日志框架" \
                    "$rel_path" \
                    "$line_num" \
                    "$catch_info" \
                    "使用 log.error(\"描述信息\", e) 替代 e.printStackTrace()"
            elif [[ "$issue_type" == "noLog" ]]; then
                json_finding \
                    "CHECK-0402" \
                    "needs_ai_review" \
                    "BLOCKER" \
                    "$_LOG_DIMENSION" \
                    "$_LOG_DIM_NAME" \
                    "异常捕获后未记录日志" \
                    "$rel_path" \
                    "$line_num" \
                    "$catch_info" \
                    "在 catch 块中添加适当的日志记录，如 log.error(\"操作失败\", e)"
            fi
        done

    done <<< "$java_files"
}

###############################################################################
# CHECK-0403 [MAJOR] Logs missing context (needs_ai_review)
#
# Log statements in Service classes that are just string literals without
# variables or placeholders — e.g. log.info("done") vs log.info("done, id={}", id)
###############################################################################
_check_0403_logs_missing_context() {
    local project_path="$1"

    log_info "CHECK-0403: Scanning for log statements missing context..."

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0403: No Java source files found, skipping."
        return
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only check Service classes for this rule
        if ! is_service "$file"; then
            continue
        fi

        local rel_path="${file#"$project_path"/}"

        # Find log statements that contain only a string literal argument (no {} placeholders,
        # no variable concatenation, no second argument).
        # Pattern: log.info("some text")  — just a single string with no format specifiers
        # We look for log calls where the argument is a single quoted string without {}
        # and no comma after the closing quote (no additional args).
        grep -nE '(log|logger|LOG)\.(trace|debug|info|warn|error)\s*\(\s*"[^"]*"\s*\)' "$file" 2>/dev/null \
            | grep -vE '\{\}' \
            | grep -vE '\+\s' \
            | while IFS=: read -r line_num line_content; do
                [[ -z "$line_num" ]] && continue

                # Trim the line content
                local trimmed
                trimmed=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0403" \
                    "needs_ai_review" \
                    "MAJOR" \
                    "$_LOG_DIMENSION" \
                    "$_LOG_DIM_NAME" \
                    "日志缺少上下文信息，建议包含关键业务参数" \
                    "$rel_path" \
                    "$line_num" \
                    "$trimmed" \
                    "添加业务上下文参数，如 log.info(\"操作完成, userId={}, orderId={}\", userId, orderId)"
            done

    done <<< "$java_files"
}

###############################################################################
# CHECK-0404 [MAJOR] Incorrect log levels (needs_ai_review)
#
# a) log.error in validation/parameter checking code (should be warn or info)
# b) log.info in catch blocks (should usually be error or warn)
###############################################################################
_check_0404_incorrect_log_levels() {
    local project_path="$1"

    log_info "CHECK-0404: Scanning for incorrect log levels..."

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0404: No Java source files found, skipping."
        return
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local rel_path="${file#"$project_path"/}"

        # --- Sub-check A: log.error in validation/parameter checking context ---
        # Look for log.error near common validation patterns (parameter checks,
        # IllegalArgumentException, @Valid, validation failure, etc.)
        grep -nE '(log|logger|LOG)\.error\s*\(' "$file" 2>/dev/null \
            | while IFS=: read -r line_num line_content; do
                [[ -z "$line_num" ]] && continue

                # Check surrounding context (5 lines before) for validation patterns
                local start_line=$(( line_num > 5 ? line_num - 5 : 1 ))
                local context
                context=$(awk -v s="$start_line" -v e="$line_num" 'NR >= s && NR <= e' "$file")

                if printf '%s' "$context" | grep -qEi '(param|argument|valid|check|empty|null|blank|require|assert|IllegalArgument|BindingResult|MethodArgumentNotValid|ConstraintViolation)'; then
                    local trimmed
                    trimmed=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                    json_finding \
                        "CHECK-0404" \
                        "needs_ai_review" \
                        "MAJOR" \
                        "$_LOG_DIMENSION" \
                        "$_LOG_DIM_NAME" \
                        "参数校验/验证场景使用了 log.error，建议使用 warn 或 info 级别" \
                        "$rel_path" \
                        "$line_num" \
                        "$trimmed" \
                        "参数校验失败属于业务预期，建议使用 log.warn() 而非 log.error()"
                fi
            done

        # --- Sub-check B: log.info inside catch blocks ---
        # Use awk to find log.info calls that are inside catch blocks
        awk '
        BEGIN {
            in_catch = 0
            catch_depth = 0
        }

        /catch[[:space:]]*\(/ {
            in_catch = 0
            catch_depth = 0
        }

        /catch[[:space:]]*\(/ {
            line = $0
            n = gsub(/{/, "{", line)
            if (n > 0) {
                in_catch = 1
                line2 = $0
                o = gsub(/{/, "{", line2)
                c = gsub(/}/, "}", line2)
                catch_depth = o - c
            }
            next
        }

        !in_catch && catch_depth == 0 && /{/ && _saw_catch {
            in_catch = 1
            line = $0
            o = gsub(/{/, "{", line)
            c = gsub(/}/, "}", line)
            catch_depth = o - c
            _saw_catch = 0
            next
        }

        in_catch {
            line = $0
            o = gsub(/{/, "{", line)
            c = gsub(/}/, "}", line)
            catch_depth += o - c

            if ($0 ~ /(log|logger|LOG)\.info[[:space:]]*\(/) {
                # Extract the trimmed line
                content = $0
                gsub(/^[[:space:]]+/, "", content)
                gsub(/[[:space:]]+$/, "", content)
                print NR ":" content
            }

            if (catch_depth <= 0) {
                in_catch = 0
            }
        }
        ' "$file" | while IFS=: read -r line_num line_content; do
            [[ -z "$line_num" ]] && continue

            json_finding \
                "CHECK-0404" \
                "needs_ai_review" \
                "MAJOR" \
                "$_LOG_DIMENSION" \
                "$_LOG_DIM_NAME" \
                "catch 块中使用了 log.info，异常场景建议使用 error 或 warn 级别" \
                "$rel_path" \
                "$line_num" \
                "$line_content" \
                "异常处理中应使用 log.error(\"描述\", e) 或 log.warn() 记录，而非 log.info()"
        done

    done <<< "$java_files"
}
