#!/usr/bin/env bash
# ==============================================================================
# check-api-validation.sh - API Parameter Validation checks
#
# Checks:
#   CHECK-1001 [BLOCKER] Missing @Valid/@Validated on @RequestBody
#   CHECK-1002 [BLOCKER] Request VO/DTO missing validation annotations
#   CHECK-1003 [MAJOR]   File upload without type/size validation
#
# Provides: check_api_validation PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding, json_finding_with_context,
#           find_java_files, find_yaml_configs, find_properties_configs,
#           is_controller, log_info
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _VALID_DIM_NUMBER=10
readonly _VALID_DIM_NAME="参数校验与 XSS 防范"

# ==============================================================================
# CHECK-1001: Missing @Valid/@Validated on @RequestBody
# ==============================================================================

# _check_1001_request_body_validation PROJECT_PATH
#   Scan Controller files for methods with @RequestBody that lack
#   @Valid or @Validated on the same parameter.
#   Handles multi-line method signatures via awk.
_check_1001_request_body_validation() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        # Only check Controller files
        is_controller "$java_file" || continue

        local rel_path="${java_file#"$project_path"/}"

        # Use awk to handle multi-line method signatures.
        # Strategy:
        #   1. Collect lines that form a method signature (from @*Mapping or
        #      public/protected/private with parentheses through the closing ')').
        #   2. Once a complete signature is assembled, check if it contains
        #      @RequestBody without a preceding @Valid or @Validated.
        #
        # Output format: "LINENUM|CODE"
        #   LINENUM = line where @RequestBody appears
        #   CODE    = the trimmed line content with @RequestBody
        local hits
        hits=$(awk '
        BEGIN {
            collecting = 0
            sig = ""
            start_line = 0
            # Track individual line contents and their line numbers
            delete line_contents
            delete line_numbers
            line_count = 0
        }

        # Detect start of a mapping-annotated method or method declaration
        # We start collecting when we see @*Mapping or a method declaration
        # that has an opening paren
        /@(Get|Post|Put|Delete|Patch|Request)Mapping/ {
            collecting = 1
            sig = ""
            start_line = NR
            line_count = 0
        }

        collecting == 1 {
            sig = sig " " $0
            line_count++
            line_contents[line_count] = $0
            line_numbers[line_count] = NR

            # Check if we have the complete signature (closing paren + opening brace or ;)
            # We look for the closing ) that ends the parameter list
            if (sig ~ /\)[ \t]*(throws[ \t]+[A-Za-z0-9_,. \t]+)?[ \t]*\{/ || \
                sig ~ /\)[ \t]*(throws[ \t]+[A-Za-z0-9_,. \t]+)?[ \t]*;/) {

                # Full signature collected. Check for @RequestBody without @Valid/@Validated.
                # We need to find each @RequestBody and check if @Valid or @Validated
                # appears before it (on the same parameter).

                # Simple approach: check if @RequestBody exists in the signature
                if (sig ~ /@RequestBody/) {
                    # Check if @Valid or @Validated is NOT present near @RequestBody
                    # A valid pattern would be: @Valid @RequestBody or @Validated @RequestBody
                    # or @RequestBody @Valid (order can vary)
                    #
                    # We check: does @Valid or @Validated appear in the signature at all?
                    # More precise: for each @RequestBody, is there a @Valid(ated)? nearby?
                    has_validation = 0
                    if (sig ~ /@Valid[[:space:]]/ || sig ~ /@Valid[^a-zA-Z]/ || \
                        sig ~ /@Validated/) {
                        has_validation = 1
                    }
                    # Edge: @Valid at end of signature segment (unlikely but handle)
                    if (sig ~ /@Valid$/) {
                        has_validation = 1
                    }

                    if (has_validation == 0) {
                        # Find the line with @RequestBody for reporting
                        for (i = 1; i <= line_count; i++) {
                            if (line_contents[i] ~ /@RequestBody/) {
                                # Trim leading/trailing whitespace
                                gsub(/^[[:space:]]+/, "", line_contents[i])
                                gsub(/[[:space:]]+$/, "", line_contents[i])
                                print line_numbers[i] "|" line_contents[i]
                                break
                            }
                        }
                    }
                }

                # Reset
                collecting = 0
                sig = ""
                line_count = 0
                delete line_contents
                delete line_numbers
            }
        }

        # Safety: if we have been collecting for too many lines, reset
        collecting == 1 && line_count > 30 {
            collecting = 0
            sig = ""
            line_count = 0
            delete line_contents
            delete line_numbers
        }
        ' "$java_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%|*}"
            local line_content="${hit#*|}"

            json_finding \
                "CHECK-1001" \
                "confirmed" \
                "BLOCKER" \
                "$_VALID_DIM_NUMBER" \
                "$_VALID_DIM_NAME" \
                "@RequestBody parameter missing @Valid/@Validated annotation" \
                "$rel_path" \
                "$line_num" \
                "$line_content" \
                "Add @Valid or @Validated before @RequestBody to enable bean validation. Example: public Response<?> create(@RequestBody @Valid CreateRequest req)"
        done <<< "$hits"
    done <<< "$java_files"
}

# ==============================================================================
# CHECK-1002: Request VO/DTO missing validation annotations
# ==============================================================================

# _check_1002_dto_validation PROJECT_PATH
#   Find DTO/VO/Request/Param classes and check if any of their fields
#   have validation annotations. Flag classes with no validation annotations.
_check_1002_dto_validation() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    # Validation annotation pattern
    local validation_pattern='@(NotNull|NotBlank|NotEmpty|Size|Min|Max|Pattern|Email|Positive|PositiveOrZero|Negative|NegativeOrZero|Past|PastOrPresent|Future|FutureOrPresent|Digits|DecimalMin|DecimalMax|AssertTrue|AssertFalse|Valid)\b'

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        local rel_path="${java_file#"$project_path"/}"

        # Filter by package path: only check files in dto/vo/request/param packages
        # Match paths like: /dto/, /vo/, /request/, /param/, /command/, /form/
        # Also match by class name suffix: *DTO.java, *Dto.java, *VO.java, *Vo.java,
        # *Request.java, *Param.java, *Form.java, *Command.java
        local is_dto=0

        # Check by path pattern
        if printf '%s' "$rel_path" | grep -qE '/(dto|vo|request|param|command|form)/' 2>/dev/null; then
            is_dto=1
        fi

        # Check by filename suffix
        if [[ $is_dto -eq 0 ]]; then
            local basename
            basename=$(basename "$java_file" .java)
            if printf '%s' "$basename" | grep -qE '(DTO|Dto|VO|Vo|Request|Param|Form|Command|Req|Cmd)$' 2>/dev/null; then
                is_dto=1
            fi
        fi

        if [[ $is_dto -eq 0 ]]; then
            continue
        fi

        # Skip interfaces, enums, and abstract classes
        if grep -qE '^\s*(public\s+)?(abstract\s+)?(interface|enum)\s' "$java_file" 2>/dev/null; then
            continue
        fi

        # Check if the file has any validation annotations on fields
        local has_validation=0
        if grep -qE "$validation_pattern" "$java_file" 2>/dev/null; then
            has_validation=1
        fi

        if [[ $has_validation -eq 0 ]]; then
            # Count the number of fields to determine if this is a real DTO
            # (skip classes with no fields, e.g. marker interfaces)
            local field_count
            field_count=$(grep -cE '^\s*(private|protected|public)\s+\S+\s+\w+\s*[;=]' "$java_file" 2>/dev/null) || field_count=0

            # Also count record components (Java records)
            local record_match
            record_match=$(grep -cE '^\s*(public\s+)?record\s+\w+\s*\(' "$java_file" 2>/dev/null) || record_match=0

            # Skip if no fields and not a record
            if [[ $field_count -eq 0 && $record_match -eq 0 ]]; then
                continue
            fi

            # Extract class declaration line for context
            local class_line
            class_line=$(grep -n -E '^\s*(public\s+)?(class|record)\s+\w+' "$java_file" 2>/dev/null | head -1) || class_line=""

            local decl_line_num=""
            local decl_content=""
            if [[ -n "$class_line" ]]; then
                decl_line_num="${class_line%%:*}"
                decl_content="${class_line#*:}"
                decl_content=$(printf '%s' "$decl_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            fi

            # Build context JSON with field count for AI review
            local ctx_json
            ctx_json=$(printf '{"fieldCount":%d,"isRecord":%s,"classDeclaration":"%s"}' \
                "$field_count" \
                "$(if [[ $record_match -gt 0 ]]; then printf 'true'; else printf 'false'; fi)" \
                "$(json_escape "$decl_content")")

            json_finding_with_context \
                "CHECK-1002" \
                "needs_ai_review" \
                "BLOCKER" \
                "$_VALID_DIM_NUMBER" \
                "$_VALID_DIM_NAME" \
                "Request DTO/VO class has no bean validation annotations on any field" \
                "$rel_path" \
                "$ctx_json"
        fi
    done <<< "$java_files"
}

# ==============================================================================
# CHECK-1003: File upload without type/size validation
# ==============================================================================

# _check_1003_file_upload_validation PROJECT_PATH
#   Find controller methods that accept MultipartFile and check whether
#   file size/type validation is configured.
_check_1003_file_upload_validation() {
    local project_path="$1"

    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    # First, check global multipart configuration
    local has_global_size_config=0

    # Check YAML config files
    local yaml_configs
    yaml_configs=$(find_yaml_configs "$project_path")
    if [[ -n "$yaml_configs" ]]; then
        while IFS= read -r config_file; do
            [[ -z "$config_file" ]] && continue
            [[ ! -f "$config_file" ]] && continue
            if grep -qE 'max-file-size|max-request-size|maxFileSize|maxRequestSize' "$config_file" 2>/dev/null; then
                has_global_size_config=1
                break
            fi
        done <<< "$yaml_configs"
    fi

    # Check properties config files
    if [[ $has_global_size_config -eq 0 ]]; then
        local prop_configs
        prop_configs=$(find_properties_configs "$project_path")
        if [[ -n "$prop_configs" ]]; then
            while IFS= read -r config_file; do
                [[ -z "$config_file" ]] && continue
                [[ ! -f "$config_file" ]] && continue
                if grep -qE 'spring\.servlet\.multipart\.(max-file-size|max-request-size)' "$config_file" 2>/dev/null; then
                    has_global_size_config=1
                    break
                fi
            done <<< "$prop_configs"
        fi
    fi

    # Now scan controller files for MultipartFile parameters
    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        # Only check Controller files
        is_controller "$java_file" || continue

        local rel_path="${java_file#"$project_path"/}"

        # Find methods accepting MultipartFile
        local hits
        hits=$(grep -n 'MultipartFile' "$java_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%:*}"
            local line_content="${hit#*:}"
            line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Skip import lines
            if printf '%s' "$line_content" | grep -qE '^\s*import\s' 2>/dev/null; then
                continue
            fi

            # Skip field declarations (not method parameters)
            if printf '%s' "$line_content" | grep -qE '^\s*(private|protected|public)\s.*MultipartFile\s+\w+\s*;' 2>/dev/null; then
                continue
            fi

            # Check if the method body (next ~30 lines) has type/size validation
            local has_local_validation=0
            local method_body
            method_body=$(sed -n "$((line_num)),$((line_num + 30))p" "$java_file" 2>/dev/null) || method_body=""

            # Look for common file validation patterns:
            #   - getContentType(), getSize(), getOriginalFilename()
            #   - file size checks, content type checks
            if printf '%s' "$method_body" | grep -qE '(getContentType|getSize|getOriginalFilename|contentType|\.size\(\)|isEmpty\(\))' 2>/dev/null; then
                has_local_validation=1
            fi

            # Build context JSON
            local ctx_json
            ctx_json=$(printf '{"hasGlobalSizeConfig":%s,"hasLocalValidation":%s,"code":"%s"}' \
                "$(if [[ $has_global_size_config -eq 1 ]]; then printf 'true'; else printf 'false'; fi)" \
                "$(if [[ $has_local_validation -eq 1 ]]; then printf 'true'; else printf 'false'; fi)" \
                "$(json_escape "$line_content")")

            json_finding_with_context \
                "CHECK-1003" \
                "needs_ai_review" \
                "MAJOR" \
                "$_VALID_DIM_NUMBER" \
                "$_VALID_DIM_NAME" \
                "File upload endpoint may lack type/size validation" \
                "$rel_path" \
                "$ctx_json"
        done <<< "$hits"
    done <<< "$java_files"
}

# ==============================================================================
# Public API
# ==============================================================================

# check_api_validation PROJECT_PATH
#   Run all API parameter validation checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_api_validation() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_api_validation: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-1001: @RequestBody missing @Valid/@Validated..."
    _check_1001_request_body_validation "$project_path"

    log_info "Running CHECK-1002: DTO/VO missing validation annotations..."
    _check_1002_dto_validation "$project_path"

    log_info "Running CHECK-1003: File upload validation..."
    _check_1003_file_upload_validation "$project_path"

    log_info "API parameter validation checks complete."
}
