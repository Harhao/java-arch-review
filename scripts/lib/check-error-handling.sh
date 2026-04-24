#!/usr/bin/env bash
# Check: Error Handling (CHECK-0501, CHECK-0502)
#
# CHECK-0501 [BLOCKER] - Missing global exception handler
#   Projects must have a @RestControllerAdvice or @ControllerAdvice class with
#   @ExceptionHandler methods to provide consistent error responses.
#
# CHECK-0502 [BLOCKER] - 5xx errors exposing stack traces
#   Stack traces must never leak to API consumers. Detects unsafe config
#   (server.error.include-stacktrace) and code patterns that return raw
#   exception details.
#
# Provides: check_error_handling PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
# Requires: common.sh

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

###############################################################################
# Constants
###############################################################################

readonly _EH_DIMENSION=5
readonly _EH_DIM_NAME="错误处理"

###############################################################################
# Public API
###############################################################################

# check_error_handling PROJECT_PATH
#   Run all error-handling checks against the given project directory.
check_error_handling() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_error_handling: invalid project path: $1"
        return 1
    }

    log_info "Running error handling checks on $project_path"

    _check_0501_global_exception_handler "$project_path"
    _check_0502_stack_trace_exposure "$project_path"
}

###############################################################################
# CHECK-0501: Missing global exception handler
###############################################################################

_check_0501_global_exception_handler() {
    local project_path="$1"

    log_info "CHECK-0501: Checking for global exception handler"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0501: No Java source files found, skipping"
        return
    fi

    # Search for files containing @RestControllerAdvice or @ControllerAdvice
    local advice_files
    advice_files=$(echo "$java_files" | xargs grep -lE '@(Rest)?ControllerAdvice' 2>/dev/null || true)

    if [[ -z "$advice_files" ]]; then
        # No advice class at all — confirmed finding
        json_finding \
            "CHECK-0501" \
            "confirmed" \
            "BLOCKER" \
            "$_EH_DIMENSION" \
            "$_EH_DIM_NAME" \
            "缺少全局异常处理器：未找到 @ControllerAdvice 或 @RestControllerAdvice 类" \
            "$project_path" \
            "" \
            "" \
            "创建一个使用 @RestControllerAdvice 注解的全局异常处理类，配合 @ExceptionHandler 统一处理异常并返回规范的错误响应体"
        return
    fi

    # Found advice class(es) — verify at least one has @ExceptionHandler
    local has_handler=false
    while IFS= read -r advice_file; do
        [[ -z "$advice_file" ]] && continue
        if grep -qE '@ExceptionHandler' "$advice_file" 2>/dev/null; then
            has_handler=true
            break
        fi
    done <<< "$advice_files"

    if [[ "$has_handler" == false ]]; then
        # Have advice class but no handler methods
        local first_advice
        first_advice=$(echo "$advice_files" | head -1)
        local relative_path="${first_advice#"$project_path"/}"

        json_finding \
            "CHECK-0501" \
            "confirmed" \
            "BLOCKER" \
            "$_EH_DIMENSION" \
            "$_EH_DIM_NAME" \
            "全局异常处理器缺少 @ExceptionHandler 方法" \
            "$relative_path" \
            "" \
            "" \
            "在 @ControllerAdvice 类中添加 @ExceptionHandler 方法来处理常见异常类型（如 Exception、RuntimeException、业务异常等）"
    fi
}

###############################################################################
# CHECK-0502: 5xx errors exposing stack traces
###############################################################################

_check_0502_stack_trace_exposure() {
    local project_path="$1"

    log_info "CHECK-0502: Checking for stack trace exposure"

    _check_0502_config_files "$project_path"
    _check_0502_code_patterns "$project_path"
}

# ---------------------------------------------------------------------------
# Sub-check: configuration files
# ---------------------------------------------------------------------------
_check_0502_config_files() {
    local project_path="$1"

    # --- YAML configs ---
    local yaml_configs
    yaml_configs=$(find_yaml_configs "$project_path")

    if [[ -n "$yaml_configs" ]]; then
        while IFS= read -r cfg_file; do
            [[ -z "$cfg_file" ]] && continue
            # Look for include-stacktrace set to "always" or "on_param"
            # YAML form: include-stacktrace: always
            local match
            match=$(grep -nE 'include-stacktrace[[:space:]]*:[[:space:]]*(always|on_param|on-param)' "$cfg_file" 2>/dev/null || true)
            if [[ -n "$match" ]]; then
                local line_num code_snippet
                line_num=$(echo "$match" | head -1 | cut -d: -f1)
                code_snippet=$(echo "$match" | head -1 | sed 's/^[0-9]*://' | sed 's/^[[:space:]]*//')
                local relative_path="${cfg_file#"$project_path"/}"

                json_finding \
                    "CHECK-0502" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_EH_DIMENSION" \
                    "$_EH_DIM_NAME" \
                    "配置文件暴露堆栈信息：server.error.include-stacktrace 设置为不安全值" \
                    "$relative_path" \
                    "$line_num" \
                    "$code_snippet" \
                    "将 server.error.include-stacktrace 设置为 never，或移除该配置（默认值即为 never）"
            fi
        done <<< "$yaml_configs"
    fi

    # --- Properties configs ---
    local props_configs
    props_configs=$(find_properties_configs "$project_path")

    if [[ -n "$props_configs" ]]; then
        while IFS= read -r cfg_file; do
            [[ -z "$cfg_file" ]] && continue
            # Properties form: server.error.include-stacktrace=always
            local match
            match=$(grep -nE 'server\.error\.include-stacktrace[[:space:]]*=[[:space:]]*(always|on_param|on-param)' "$cfg_file" 2>/dev/null || true)
            if [[ -n "$match" ]]; then
                local line_num code_snippet
                line_num=$(echo "$match" | head -1 | cut -d: -f1)
                code_snippet=$(echo "$match" | head -1 | sed 's/^[0-9]*://' | sed 's/^[[:space:]]*//')
                local relative_path="${cfg_file#"$project_path"/}"

                json_finding \
                    "CHECK-0502" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_EH_DIMENSION" \
                    "$_EH_DIM_NAME" \
                    "配置文件暴露堆栈信息：server.error.include-stacktrace 设置为不安全值" \
                    "$relative_path" \
                    "$line_num" \
                    "$code_snippet" \
                    "将 server.error.include-stacktrace 设置为 never，或移除该配置（默认值即为 never）"
            fi
        done <<< "$props_configs"
    fi
}

# ---------------------------------------------------------------------------
# Sub-check: code patterns in controllers / exception handlers
# ---------------------------------------------------------------------------
_check_0502_code_patterns() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    # --- Pattern 1: e.printStackTrace() in Controller classes ---
    local controller_files
    controller_files=$(echo "$java_files" | xargs grep -lE '@(Rest)?Controller' 2>/dev/null || true)

    if [[ -n "$controller_files" ]]; then
        while IFS= read -r ctrl_file; do
            [[ -z "$ctrl_file" ]] && continue
            local matches
            matches=$(grep -nE '\.printStackTrace[[:space:]]*\(' "$ctrl_file" 2>/dev/null || true)
            if [[ -n "$matches" ]]; then
                while IFS= read -r match_line; do
                    [[ -z "$match_line" ]] && continue
                    local line_num code_snippet
                    line_num=$(echo "$match_line" | cut -d: -f1)
                    code_snippet=$(echo "$match_line" | sed 's/^[0-9]*://' | sed 's/^[[:space:]]*//')
                    local relative_path="${ctrl_file#"$project_path"/}"

                    json_finding \
                        "CHECK-0502" \
                        "confirmed" \
                        "BLOCKER" \
                        "$_EH_DIMENSION" \
                        "$_EH_DIM_NAME" \
                        "Controller 中使用 e.printStackTrace()，可能在响应中泄露堆栈信息" \
                        "$relative_path" \
                        "$line_num" \
                        "$code_snippet" \
                        "使用日志框架（如 SLF4J）记录异常，避免在 Controller 中调用 printStackTrace()"
                done <<< "$matches"
            fi
        done <<< "$controller_files"
    fi

    # --- Pattern 2: @ExceptionHandler returning raw exception details ---
    # Search files that have @ExceptionHandler for patterns returning exception internals
    local handler_files
    handler_files=$(echo "$java_files" | xargs grep -lE '@ExceptionHandler' 2>/dev/null || true)

    if [[ -n "$handler_files" ]]; then
        while IFS= read -r handler_file; do
            [[ -z "$handler_file" ]] && continue
            local relative_path="${handler_file#"$project_path"/}"

            # Check for exception.getMessage(), exception.toString(), or returning
            # the exception object directly.
            # These are heuristics — flag for AI review.
            local suspicious_lines
            suspicious_lines=$(grep -nE '\.(getMessage|toString)[[:space:]]*\(' "$handler_file" 2>/dev/null || true)

            if [[ -n "$suspicious_lines" ]]; then
                # Collect all suspicious snippets for context
                local snippets=""
                local first_line=""
                while IFS= read -r s_line; do
                    [[ -z "$s_line" ]] && continue
                    local ln sn
                    ln=$(echo "$s_line" | cut -d: -f1)
                    sn=$(echo "$s_line" | sed 's/^[0-9]*://' | sed 's/^[[:space:]]*//')
                    if [[ -z "$first_line" ]]; then
                        first_line="$ln"
                    fi
                    if [[ -n "$snippets" ]]; then
                        snippets="$snippets | $sn"
                    else
                        snippets="$sn"
                    fi
                done <<< "$suspicious_lines"

                local context_json
                context_json=$(printf '{"reason":"@ExceptionHandler 方法中可能将异常信息直接返回给客户端","snippets":"%s"}' \
                    "$(json_escape "$snippets")")

                json_finding_with_context \
                    "CHECK-0502" \
                    "needs_ai_review" \
                    "BLOCKER" \
                    "$_EH_DIMENSION" \
                    "$_EH_DIM_NAME" \
                    "@ExceptionHandler 可能向客户端暴露异常详情（getMessage/toString）" \
                    "$relative_path" \
                    "$context_json"
            fi
        done <<< "$handler_files"
    fi
}
