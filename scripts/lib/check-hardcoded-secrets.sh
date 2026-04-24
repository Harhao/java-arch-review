#!/usr/bin/env bash
# ==============================================================================
# check-hardcoded-secrets.sh - Detect hardcoded secrets in Java/Spring Boot projects
#
# Check: CHECK-0301 [BLOCKER] - Sensitive information hardcoded
#
# Provides: check_hardcoded_secrets PROJECT_PATH
# Outputs:  JSON findings to stdout (one JSON object per line)
#
# Scans Java source files and Spring configuration files for hardcoded
# passwords, API keys, tokens, private keys, and other sensitive data.
#
# Compatibility: macOS, Linux (POSIX-compatible)
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ==============================================================================
# Constants
# ==============================================================================

readonly _HS_CHECK_ID="CHECK-0301"
readonly _HS_SEVERITY="BLOCKER"
readonly _HS_DIMENSION="3"
readonly _HS_DIM_NAME="配置管理"
readonly _HS_TITLE="敏感信息硬编码"
readonly _HS_SUGGESTION="将敏感信息移至环境变量、Spring 配置中心或使用 Jasypt 等工具加密存储。例如: 使用 \${DB_PASSWORD} 环境变量替代明文密码，或通过 Spring Cloud Config / Vault 管理敏感配置。"

# ==============================================================================
# Internal helpers
# ==============================================================================

# _mask_secret VALUE
#   Show the first 4 characters of a secret, replace the rest with ***.
#   If the value is 4 characters or fewer, mask it entirely.
_mask_secret() {
    local val="$1"
    local len=${#val}
    if [[ $len -le 4 ]]; then
        printf '***'
    else
        printf '%s***' "${val:0:4}"
    fi
}

# _is_comment LINE
#   Return 0 if the line is a comment (Java // or * style, or # for properties/yaml).
_is_comment() {
    local line="$1"
    local trimmed
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
        //*|'*'*|\#*) return 0 ;;
        *)            return 1 ;;
    esac
}

# _is_placeholder VALUE
#   Return 0 if the value looks like a placeholder / example, not a real secret.
_is_placeholder() {
    local val="$1"
    # Lowercase for comparison
    local lower
    lower=$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')

    # Spring property placeholder ${...}
    if [[ "$val" == *'${'*'}'* ]]; then
        return 0
    fi

    # Common placeholder / example patterns
    case "$lower" in
        ""|\
        "your-password-here"|\
        "your-secret-here"|\
        "your-api-key-here"|\
        "your_password_here"|\
        "your_secret_here"|\
        "your_api_key_here"|\
        "changeme"|\
        "change-me"|\
        "change_me"|\
        "password"|\
        "secret"|\
        "xxx"|\
        "xxxx"|\
        "xxxxx"|\
        "xxxxxx"|\
        "todo"|\
        "fixme"|\
        "replace-me"|\
        "replace_me"|\
        "example"|\
        "sample"|\
        "test"|\
        "default"|\
        "dummy"|\
        "placeholder"|\
        "none"|\
        "null"|\
        "empty"|\
        "n/a"|\
        "na")
            return 0
            ;;
    esac

    # Patterns that indicate placeholders
    if [[ "$lower" == *"your-"*"-here"* ]] \
        || [[ "$lower" == *"your_"*"_here"* ]] \
        || [[ "$lower" == *"<"*">"* ]] \
        || [[ "$lower" == "todo:"* ]] \
        || [[ "$lower" == "fixme:"* ]]; then
        return 0
    fi

    return 1
}

# _is_test_file FILE
#   Return 0 if the file is in a test directory or is a test file.
_is_test_file() {
    local file="$1"
    case "$file" in
        */test/*|*/tests/*|*/Test/*|*/__test__/*|*/androidTest/*) return 0 ;;
        *Test.java|*Tests.java|*IT.java|*Spec.java|*TestCase.java)  return 0 ;;
    esac
    return 1
}

# _make_relative PATH BASE
#   Make a path relative to a base directory for cleaner output.
_make_relative() {
    local path="$1" base="$2"
    printf '%s' "${path#"$base"/}"
}

# _scan_java_files PROJECT_PATH
#   Scan Java source files for hardcoded secrets.
_scan_java_files() {
    local project_path="$1"
    local files
    files=$(find_java_files "$project_path")

    [[ -z "$files" ]] && return

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        _is_test_file "$file" && continue

        local line_num=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$((line_num + 1))

            # Skip comment lines
            _is_comment "$line" && continue

            local rel_file
            rel_file=$(_make_relative "$file" "$project_path")

            # --- Pattern 1: password = "..." or password("...") ---
            if printf '%s' "$line" | grep -qiE '(password|passwd|pwd)[[:space:]]*[=:][[:space:]]*"[^"$][^"]*"'; then
                local secret_val
                secret_val=$(printf '%s' "$line" | sed -nE 's/.*[pP][aA][sS][sS][wW]([oO][rR][dD]|[wW][dD])[[:space:]]*[=:][[:space:]]*"([^"]*)".*/\2/p' | head -1)
                if [[ -n "$secret_val" ]] && ! _is_placeholder "$secret_val"; then
                    local masked
                    masked=$(_mask_secret "$secret_val")
                    local display_line
                    display_line=$(printf '%s' "$line" | sed "s/${secret_val}/${masked}/g")
                    json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                        "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                        "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                fi
            fi

            # --- Pattern 2: secret / secretKey / apiKey = "..." ---
            if printf '%s' "$line" | grep -qiE '(secret|secretKey|apiKey|api_key|secret_key)[[:space:]]*[=:][[:space:]]*"[^"$][^"]*"'; then
                local secret_val
                secret_val=$(printf '%s' "$line" | sed -nE 's/.*(secret|secretKey|apiKey|api_key|secret_key)[[:space:]]*[=:][[:space:]]*"([^"]*)".*/\2/p' | head -1)
                if [[ -n "$secret_val" ]] && ! _is_placeholder "$secret_val"; then
                    local masked
                    masked=$(_mask_secret "$secret_val")
                    local display_line
                    display_line=$(printf '%s' "$line" | sed "s/${secret_val}/${masked}/g")
                    json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                        "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                        "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                fi
            fi

            # --- Pattern 3: JDBC URL with inline credentials ---
            if printf '%s' "$line" | grep -qE 'jdbc:(mysql|postgresql|mariadb|sqlserver|oracle)://[^"]*password=' ; then
                local display_line
                display_line=$(printf '%s' "$line" | sed -E 's/(password=)([^&"]*)/\1***/g')
                json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                    "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                    "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
            fi

            # --- Pattern 4: Bearer token ---
            if printf '%s' "$line" | grep -qE 'Bearer [A-Za-z0-9_\-\.]{20,}'; then
                local token_val
                token_val=$(printf '%s' "$line" | sed -nE 's/.*Bearer ([A-Za-z0-9_\.\-]{20,}).*/\1/p' | head -1)
                if [[ -n "$token_val" ]]; then
                    local masked
                    masked=$(_mask_secret "$token_val")
                    local display_line
                    display_line=$(printf '%s' "$line" | sed "s/${token_val}/${masked}/g")
                    json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                        "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                        "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                fi
            fi

            # --- Pattern 5: AWS Access Key ---
            if printf '%s' "$line" | grep -qE 'AKIA[0-9A-Z]{16}'; then
                local aws_key
                aws_key=$(printf '%s' "$line" | sed -nE 's/.*(AKIA[0-9A-Z]{16}).*/\1/p' | head -1)
                if [[ -n "$aws_key" ]]; then
                    local masked
                    masked=$(_mask_secret "$aws_key")
                    local display_line
                    display_line=$(printf '%s' "$line" | sed "s/${aws_key}/${masked}/g")
                    json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                        "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                        "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                fi
            fi

            # --- Pattern 6: Private key markers ---
            if printf '%s' "$line" | grep -qE '\-\-\-\-\-BEGIN (RSA |EC )?PRIVATE KEY\-\-\-\-\-'; then
                json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                    "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                    "$rel_file" "$line_num" "-----BEGIN PRIVATE KEY----- [content masked]" "$_HS_SUGGESTION"
            fi

        done < "$file"
    done <<< "$files"
}

# _scan_config_files PROJECT_PATH
#   Scan YAML and properties configuration files for hardcoded secrets.
_scan_config_files() {
    local project_path="$1"

    # Collect all config files (YAML + properties)
    local config_files=""
    local yaml_files
    yaml_files=$(find_yaml_configs "$project_path")
    local prop_files
    prop_files=$(find_properties_configs "$project_path")

    if [[ -n "$yaml_files" ]]; then
        config_files="$yaml_files"
    fi
    if [[ -n "$prop_files" ]]; then
        if [[ -n "$config_files" ]]; then
            config_files="$config_files"$'\n'"$prop_files"
        else
            config_files="$prop_files"
        fi
    fi

    [[ -z "$config_files" ]] && return

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        _is_test_file "$file" && continue

        local line_num=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$((line_num + 1))

            # Skip comment lines
            _is_comment "$line" && continue

            local rel_file
            rel_file=$(_make_relative "$file" "$project_path")

            # Track whether this line already produced a finding to avoid duplicates
            local line_matched=false

            # --- YAML pattern: key: "value" or key: value (for password-like keys) ---
            # Match keys containing password, secret, api-key, api_key, token, credential
            if printf '%s' "$line" | grep -qiE '(password|passwd|pwd|secret|secret-key|secret_key|api-key|api_key|apikey|credential)[[:space:]]*[:=][[:space:]]*[^$\{]'; then
                local val=""

                # Try quoted value first: key: "value" or key: 'value'
                val=$(printf '%s' "$line" | sed -nE "s/.*[[:space:]]*[:=][[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" | head -1)

                # If no quoted value, try unquoted: key: value or key=value
                if [[ -z "$val" ]]; then
                    val=$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]*[:=][[:space:]]*([^[:space:]#]+).*/\1/p' | head -1)
                fi

                # Skip empty, placeholder, and Spring expression values
                if [[ -n "$val" ]] && ! _is_placeholder "$val"; then
                    # Skip if value starts with ${ (Spring placeholder)
                    if [[ "$val" != '${'* && "$val" != '@'* ]]; then
                        local masked
                        masked=$(_mask_secret "$val")
                        local display_line
                        # Use a safe masking approach - replace the value portion
                        display_line=$(printf '%s' "$line" | sed "s|${val}|${masked}|g" 2>/dev/null || printf '%s' "$line")
                        json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                            "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                            "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                        line_matched=true
                    fi
                fi
            fi

            # --- JDBC URL with inline credentials in config files ---
            # Skip if the line was already matched by the password-key pattern above
            if [[ "$line_matched" == false ]] && printf '%s' "$line" | grep -qE 'jdbc:(mysql|postgresql|mariadb|sqlserver|oracle)://[^#]*password='; then
                local display_line
                display_line=$(printf '%s' "$line" | sed -E 's/(password=)([^&"[:space:]#]*)/\1***/g')
                json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                    "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                    "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
            fi

            # --- AWS Access Key in config ---
            if printf '%s' "$line" | grep -qE 'AKIA[0-9A-Z]{16}'; then
                local aws_key
                aws_key=$(printf '%s' "$line" | sed -nE 's/.*(AKIA[0-9A-Z]{16}).*/\1/p' | head -1)
                if [[ -n "$aws_key" ]]; then
                    local masked
                    masked=$(_mask_secret "$aws_key")
                    local display_line
                    display_line=$(printf '%s' "$line" | sed "s/${aws_key}/${masked}/g")
                    json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                        "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                        "$rel_file" "$line_num" "$display_line" "$_HS_SUGGESTION"
                fi
            fi

            # --- Private key in config ---
            if printf '%s' "$line" | grep -qE '\-\-\-\-\-BEGIN (RSA |EC )?PRIVATE KEY\-\-\-\-\-'; then
                json_finding "$_HS_CHECK_ID" "confirmed" "$_HS_SEVERITY" \
                    "$_HS_DIMENSION" "$_HS_DIM_NAME" "$_HS_TITLE" \
                    "$rel_file" "$line_num" "-----BEGIN PRIVATE KEY----- [content masked]" "$_HS_SUGGESTION"
            fi

        done < "$file"
    done <<< "$config_files"
}

# ==============================================================================
# Public API
# ==============================================================================

# check_hardcoded_secrets PROJECT_PATH
#   Scan a Java/Spring Boot project for hardcoded secrets.
#   Outputs JSON findings to stdout (one per line).
#
#   Checks:
#     - Hardcoded passwords, secrets, API keys in Java source files
#     - Hardcoded credentials in YAML and properties config files
#     - JDBC URLs with inline credentials
#     - Bearer tokens, AWS keys, and private key markers
#
#   Excludes:
#     - Test files
#     - Comment lines
#     - Placeholder / example values
#     - Spring property placeholders ${...}
check_hardcoded_secrets() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "Invalid project path: $1"
        return 1
    }

    log_info "Scanning for hardcoded secrets in: $project_path"

    _scan_java_files "$project_path"
    _scan_config_files "$project_path"

    log_info "Hardcoded secrets scan complete."
}
