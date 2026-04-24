#!/usr/bin/env bash
# ==============================================================================
# check-config.sh - Configuration Management checks
#
# Checks:
#   CHECK-0302 [MAJOR] No multi-environment configuration
#   CHECK-0303 [MAJOR] Config values not injected via Spring
#
# Provides: check_config PROJECT_PATH
# Outputs:  JSON findings to stdout (one per line)
#
# Compatibility: macOS, Linux, Windows Git Bash
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension metadata
readonly _CONFIG_DIMENSION=3
readonly _CONFIG_DIM_NAME="配置管理"

###############################################################################
# Public API
###############################################################################

# check_config PROJECT_PATH
#   Run all configuration management checks against the given project.
check_config() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "Invalid project path: $1"
        return 1
    }

    log_info "Running configuration management checks on: $project_path"

    _check_0302_multi_env_config "$project_path"
    _check_0303_config_not_injected "$project_path"
}

###############################################################################
# CHECK-0302 [MAJOR] No multi-environment configuration
#
# Projects should have profile-specific config files:
#   - application-dev.yml + application-prod.yml (or .properties)
#   - bootstrap-*.yml if using Spring Cloud
# A project that only has a single application.yml/properties with no
# profile variants is flagged.
###############################################################################

_check_0302_multi_env_config() {
    local project_path="$1"

    log_info "CHECK-0302: Checking for multi-environment configuration files"

    # Collect all application/bootstrap config files (YAML + properties)
    local all_configs
    all_configs=$(
        {
            find_yaml_configs "$project_path"
            find_properties_configs "$project_path"
        } | sort -u
    )

    # If there are no config files at all, nothing to check
    if [[ -z "$all_configs" ]]; then
        log_info "CHECK-0302: No Spring config files found, skipping"
        return
    fi

    # Separate base configs from profile configs.
    # Base configs: application.yml, application.yaml, application.properties,
    #               bootstrap.yml, bootstrap.yaml, bootstrap.properties
    # Profile configs: application-{profile}.yml, bootstrap-{profile}.properties, etc.
    local has_base=false
    local has_profile=false

    while IFS= read -r config_file; do
        [[ -z "$config_file" ]] && continue
        local basename
        basename=$(basename "$config_file")

        # Check if this is a profile-specific config (contains a hyphen after the prefix)
        # Pattern: application-*.yml, application-*.yaml, application-*.properties
        #          bootstrap-*.yml, bootstrap-*.yaml, bootstrap-*.properties
        if [[ "$basename" =~ ^(application|bootstrap)-[a-zA-Z].+(\.yml|\.yaml|\.properties)$ ]]; then
            has_profile=true
        elif [[ "$basename" =~ ^(application|bootstrap)(\.yml|\.yaml|\.properties)$ ]]; then
            has_base=true
        fi
    done <<< "$all_configs"

    # Flag if we have base config(s) but no profile-specific configs
    if [[ "$has_base" == true && "$has_profile" == false ]]; then
        # Find a representative base config file to report
        local report_file=""
        while IFS= read -r config_file; do
            [[ -z "$config_file" ]] && continue
            local bn
            bn=$(basename "$config_file")
            if [[ "$bn" =~ ^(application|bootstrap)(\.yml|\.yaml|\.properties)$ ]]; then
                # Make path relative to project root
                report_file="${config_file#"$project_path"/}"
                break
            fi
        done <<< "$all_configs"

        json_finding \
            "CHECK-0302" \
            "confirmed" \
            "MAJOR" \
            "$_CONFIG_DIMENSION" \
            "$_CONFIG_DIM_NAME" \
            "未使用多环境配置：仅发现基础配置文件，缺少 profile 配置（如 application-dev.yml, application-prod.yml）" \
            "${report_file:-unknown}" \
            "" \
            "" \
            "添加多环境配置文件，至少包含 application-dev.yml 和 application-prod.yml，避免将生产凭证提交到代码仓库"
    else
        log_info "CHECK-0302: Multi-environment config found, OK"
    fi
}

###############################################################################
# CHECK-0303 [MAJOR] Config values not injected via Spring
#
# Detects Java source code that reads configuration directly instead of using
# Spring's @Value or @ConfigurationProperties:
#   - System.getenv(
#   - System.getProperty(
#   - new FileInputStream("config  (reading config files directly)
#   - Properties().load( or Properties props ... .load( pattern
#
# Test files are excluded.
###############################################################################

_check_0303_config_not_injected() {
    local project_path="$1"

    log_info "CHECK-0303: Checking for config values not injected via Spring"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        log_info "CHECK-0303: No Java source files found, skipping"
        return
    fi

    # Patterns to detect direct config reading.
    # Each entry: "pattern|description"
    local -a patterns=(
        'System\.getenv\s*\(|直接通过 System.getenv() 读取环境变量'
        'System\.getProperty\s*\(|直接通过 System.getProperty() 读取系统属性'
        'new\s+FileInputStream\s*\(\s*"config|直接通过 FileInputStream 读取配置文件'
        'new\s+Properties\s*\(\s*\)|手动创建 Properties 对象加载配置'
    )

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue

        local relative_file="${java_file#"$project_path"/}"

        for entry in "${patterns[@]}"; do
            local pattern="${entry%%|*}"
            local description="${entry##*|}"

            # Use grep -nE for line numbers; portable across macOS and Linux
            local matches
            matches=$(grep -nE "$pattern" "$java_file" 2>/dev/null || true)

            if [[ -z "$matches" ]]; then
                continue
            fi

            # For the Properties pattern, also verify there is a .load( call nearby
            if [[ "$pattern" == 'new\s+Properties\s*\(\s*\)' ]]; then
                if ! grep -qE '\.load\s*\(' "$java_file" 2>/dev/null; then
                    continue
                fi
            fi

            # Emit one finding per match line
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue

                local line_num="${match_line%%:*}"
                local code_snippet="${match_line#*:}"
                # Trim leading/trailing whitespace from code snippet
                code_snippet=$(printf '%s' "$code_snippet" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0303" \
                    "confirmed" \
                    "MAJOR" \
                    "$_CONFIG_DIMENSION" \
                    "$_CONFIG_DIM_NAME" \
                    "配置值未通过 Spring 注入：${description}" \
                    "$relative_file" \
                    "$line_num" \
                    "$code_snippet" \
                    "使用 @Value 或 @ConfigurationProperties 注入配置值，避免直接读取系统环境变量或属性文件"
            done <<< "$matches"
        done
    done <<< "$java_files"
}
