#!/usr/bin/env bash
# ==============================================================================
# check-data-storage.sh - Data Storage Design checks
#
# Checks:
#   CHECK-2001 [BLOCKER] Queries missing ownership filter (needs_ai_review)
#   CHECK-2002 [MAJOR]   Tables missing timestamp fields (needs_ai_review)
#   CHECK-2003 [MAJOR]   No soft delete mechanism (needs_ai_review)
#   CHECK-2004 [MAJOR]   Plaintext password storage (needs_ai_review)
#
# Provides: check_data_storage PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding_with_context, find_xml_mappers,
#           find_java_files, log_info, log_warn
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _DS_DIM_NUMBER=15
readonly _DS_DIM_NAME="数据存储设计"

# ==============================================================================
# Internal helpers
# ==============================================================================

# _find_sql_migration_files DIR
#   Find SQL migration files (Flyway, Liquibase SQL changelogs, generic schema).
_find_sql_migration_files() {
    local dir="${1:-.}"
    find "$dir" -type f -name '*.sql' \
        ! -path '*/target/*' \
        ! -path '*/build/*' \
        ! -path '*/node_modules/*' \
        2>/dev/null || true
}

# _find_entity_files DIR
#   Find Java entity/model classes by looking for common ORM annotations.
#   Returns file paths that contain @Entity, @Table, @TableName, or are in
#   entity/model/domain/po directories.
_find_entity_files() {
    local dir="${1:-.}"
    local java_files
    java_files=$(find_java_files "$dir")

    if [[ -z "$java_files" ]]; then
        return
    fi

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        [[ ! -f "$f" ]] && continue

        # Match by annotation or by conventional directory name
        if grep -qE '@(Entity|Table|TableName)\b' "$f" 2>/dev/null; then
            printf '%s\n' "$f"
        elif printf '%s' "$f" | grep -qE '/(entity|model|domain|po|pojo)/' 2>/dev/null; then
            # Only include if it looks like a class (has class keyword)
            if grep -qE '^\s*(public\s+)?class\s+' "$f" 2>/dev/null; then
                printf '%s\n' "$f"
            fi
        fi
    done <<< "$java_files"
}

# ==============================================================================
# CHECK-2001: Queries missing ownership filter
# ==============================================================================

# _check_2001_xml_mappers PROJECT_PATH
#   Scan MyBatis XML SELECT queries for missing user_id / tenant_id filters.
_check_2001_xml_mappers() {
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

        # Extract SELECT statement blocks with their id and starting line number.
        # We use awk to find <select ...> blocks and check for ownership filters.
        local hits
        hits=$(awk '
            BEGIN { in_select = 0; block = ""; start_line = 0; select_id = "" }
            /<select[[:space:]]/ {
                in_select = 1
                block = $0
                start_line = NR
                # Extract id attribute
                match($0, /id="([^"]*)"/, arr)
                if (RSTART > 0) {
                    select_id = arr[1]
                } else {
                    select_id = "(unknown)"
                }
                # Check if single-line select (self-closing is unlikely but handle it)
                if ($0 ~ /<\/select>/) {
                    in_select = 0
                    # Check for ownership filter
                    lower_block = tolower(block)
                    if (lower_block !~ /user_id/ && lower_block !~ /userid/ && \
                        lower_block !~ /tenant_id/ && lower_block !~ /tenantid/ && \
                        lower_block !~ /owner_id/ && lower_block !~ /ownerid/ && \
                        lower_block !~ /created_by/ && lower_block !~ /createdby/) {
                        print start_line ":" select_id
                    }
                    block = ""
                }
                next
            }
            in_select {
                block = block "\n" $0
                if ($0 ~ /<\/select>/) {
                    in_select = 0
                    lower_block = tolower(block)
                    if (lower_block !~ /user_id/ && lower_block !~ /userid/ && \
                        lower_block !~ /tenant_id/ && lower_block !~ /tenantid/ && \
                        lower_block !~ /owner_id/ && lower_block !~ /ownerid/ && \
                        lower_block !~ /created_by/ && lower_block !~ /createdby/) {
                        print start_line ":" select_id
                    }
                    block = ""
                }
            }
        ' "$mapper_file" 2>/dev/null) || true

        if [[ -z "$hits" ]]; then
            continue
        fi

        while IFS= read -r hit; do
            [[ -z "$hit" ]] && continue

            local line_num="${hit%%:*}"
            local select_id="${hit#*:}"

            local context_json
            context_json=$(printf '{"mapper":"%s","selectId":"%s","line":%s,"reason":"SELECT query does not reference user_id/tenant_id/owner_id in WHERE clause — may lack ownership filtering"}' \
                "$(json_escape "$rel_path")" \
                "$(json_escape "$select_id")" \
                "$line_num")

            json_finding_with_context \
                "CHECK-2001" \
                "needs_ai_review" \
                "BLOCKER" \
                "$_DS_DIM_NUMBER" \
                "$_DS_DIM_NAME" \
                "Query <select id=\"${select_id}\"> may lack ownership/tenant filter" \
                "$rel_path" \
                "$context_json"
        done <<< "$hits"
    done <<< "$mapper_files"
}

# _check_2001_java_queries PROJECT_PATH
#   Scan Java files for query methods (JPA @Query, MyBatis-Plus QueryWrapper)
#   that don't include ownership conditions.
_check_2001_java_queries() {
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

        # Check @Query annotations with SELECT that lack ownership filter
        local query_hits
        query_hits=$(grep -n '@Query' "$java_file" 2>/dev/null) || true

        if [[ -n "$query_hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"

                # Read the annotation value — may span a few lines
                local context
                context=$(sed -n "${line_num},$((line_num + 5))p" "$java_file" 2>/dev/null) || true

                # Only flag SELECT queries
                if ! printf '%s' "$context" | grep -qi 'SELECT' 2>/dev/null; then
                    continue
                fi

                # Check for ownership filter presence
                local context_lower
                context_lower=$(printf '%s' "$context" | tr '[:upper:]' '[:lower:]')

                if printf '%s' "$context_lower" | grep -qE 'user_id|userid|tenant_id|tenantid|owner_id|ownerid|created_by|createdby' 2>/dev/null; then
                    continue
                fi

                line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                local context_json
                context_json=$(printf '{"file":"%s","line":%s,"annotation":"%s","reason":"@Query SELECT does not reference ownership/tenant column — verify if this query needs data isolation"}' \
                    "$(json_escape "$rel_path")" \
                    "$line_num" \
                    "$(json_escape "$line_content")")

                json_finding_with_context \
                    "CHECK-2001" \
                    "needs_ai_review" \
                    "BLOCKER" \
                    "$_DS_DIM_NUMBER" \
                    "$_DS_DIM_NAME" \
                    "@Query SELECT may lack ownership/tenant filter" \
                    "$rel_path" \
                    "$context_json"
            done <<< "$query_hits"
        fi
    done <<< "$java_files"
}

# ==============================================================================
# CHECK-2002: Tables missing timestamp fields
# ==============================================================================

# _check_2002_entity_classes PROJECT_PATH
#   Scan entity/model classes for missing create/update timestamp fields.
_check_2002_entity_classes() {
    local project_path="$1"

    local entity_files
    entity_files=$(_find_entity_files "$project_path")

    if [[ -z "$entity_files" ]]; then
        return
    fi

    # Timestamp field patterns (case-insensitive match)
    local ts_pattern='createTime|createdAt|created_at|gmtCreate|gmt_create|createDate|createdDate'
    local update_ts_pattern='updateTime|updatedAt|updated_at|gmtModified|gmt_modified|updateDate|modifiedDate'

    while IFS= read -r entity_file; do
        [[ -z "$entity_file" ]] && continue
        [[ ! -f "$entity_file" ]] && continue

        local rel_path="${entity_file#"$project_path"/}"
        local file_content
        file_content=$(cat "$entity_file" 2>/dev/null) || continue

        # Extract class name
        local class_name
        class_name=$(printf '%s' "$file_content" | grep -oE 'class[[:space:]]+[A-Z][A-Za-z0-9_]+' | head -1 | awk '{print $2}') || true
        [[ -z "$class_name" ]] && class_name="(unknown)"

        local has_create_ts=false
        local has_update_ts=false

        # Check field declarations and getter methods
        if printf '%s' "$file_content" | grep -qEi "$ts_pattern" 2>/dev/null; then
            has_create_ts=true
        fi
        if printf '%s' "$file_content" | grep -qEi "$update_ts_pattern" 2>/dev/null; then
            has_update_ts=true
        fi

        local missing_fields=""
        if [[ "$has_create_ts" == "false" ]]; then
            missing_fields="createTime/createdAt"
        fi
        if [[ "$has_update_ts" == "false" ]]; then
            if [[ -n "$missing_fields" ]]; then
                missing_fields="${missing_fields}, updateTime/updatedAt"
            else
                missing_fields="updateTime/updatedAt"
            fi
        fi

        if [[ -n "$missing_fields" ]]; then
            local context_json
            context_json=$(printf '{"entity":"%s","file":"%s","missingFields":"%s","reason":"Entity class does not declare standard audit timestamp fields (%s). Consider adding create/update timestamps for data traceability."}' \
                "$(json_escape "$class_name")" \
                "$(json_escape "$rel_path")" \
                "$(json_escape "$missing_fields")" \
                "$(json_escape "$missing_fields")")

            json_finding_with_context \
                "CHECK-2002" \
                "needs_ai_review" \
                "MAJOR" \
                "$_DS_DIM_NUMBER" \
                "$_DS_DIM_NAME" \
                "Entity ${class_name} may be missing timestamp fields: ${missing_fields}" \
                "$rel_path" \
                "$context_json"
        fi
    done <<< "$entity_files"
}

# _check_2002_sql_migrations PROJECT_PATH
#   Scan SQL migration files for CREATE TABLE statements missing timestamp columns.
_check_2002_sql_migrations() {
    local project_path="$1"

    local sql_files
    sql_files=$(_find_sql_migration_files "$project_path")

    if [[ -z "$sql_files" ]]; then
        return
    fi

    local ts_col_pattern='create_time|created_at|gmt_create|create_date|created_date'
    local update_col_pattern='update_time|updated_at|gmt_modified|update_date|modified_date'

    while IFS= read -r sql_file; do
        [[ -z "$sql_file" ]] && continue
        [[ ! -f "$sql_file" ]] && continue

        local rel_path="${sql_file#"$project_path"/}"

        # Extract CREATE TABLE blocks using awk
        # Output format: "LINE_NUM:TABLE_NAME:BLOCK_CONTENT"
        local create_blocks
        create_blocks=$(awk '
            BEGIN { IGNORECASE = 1 }
            /CREATE[[:space:]]+TABLE/ {
                start_line = NR
                block = $0
                # Extract table name - handle various quoting styles
                match($0, /CREATE[[:space:]]+TABLE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?[`"\[]?([A-Za-z_][A-Za-z0-9_]*)[`"\]]?/, arr)
                tname = (RSTART > 0) ? arr[2] : "(unknown)"
                if ($0 ~ /;/) {
                    print start_line ":" tname ":" block
                    next
                }
                in_create = 1
                next
            }
            in_create {
                block = block "\n" $0
                if ($0 ~ /;/) {
                    in_create = 0
                    print start_line ":" tname ":" block
                }
            }
        ' "$sql_file" 2>/dev/null) || true

        if [[ -z "$create_blocks" ]]; then
            continue
        fi

        while IFS= read -r block_info; do
            [[ -z "$block_info" ]] && continue

            local line_num="${block_info%%:*}"
            local rest="${block_info#*:}"
            local table_name="${rest%%:*}"
            local block_content="${rest#*:}"
            local block_lower
            block_lower=$(printf '%s' "$block_content" | tr '[:upper:]' '[:lower:]')

            local missing_cols=""
            if ! printf '%s' "$block_lower" | grep -qE "$ts_col_pattern" 2>/dev/null; then
                missing_cols="create_time/created_at"
            fi
            if ! printf '%s' "$block_lower" | grep -qE "$update_col_pattern" 2>/dev/null; then
                if [[ -n "$missing_cols" ]]; then
                    missing_cols="${missing_cols}, update_time/updated_at"
                else
                    missing_cols="update_time/updated_at"
                fi
            fi

            if [[ -n "$missing_cols" ]]; then
                local context_json
                context_json=$(printf '{"table":"%s","file":"%s","line":%s,"missingColumns":"%s","reason":"CREATE TABLE %s does not include standard audit timestamp columns (%s)."}' \
                    "$(json_escape "$table_name")" \
                    "$(json_escape "$rel_path")" \
                    "$line_num" \
                    "$(json_escape "$missing_cols")" \
                    "$(json_escape "$table_name")" \
                    "$(json_escape "$missing_cols")")

                json_finding_with_context \
                    "CHECK-2002" \
                    "needs_ai_review" \
                    "MAJOR" \
                    "$_DS_DIM_NUMBER" \
                    "$_DS_DIM_NAME" \
                    "Table ${table_name} may be missing timestamp columns: ${missing_cols}" \
                    "$rel_path" \
                    "$context_json"
            fi
        done <<< "$create_blocks"
    done <<< "$sql_files"
}

# ==============================================================================
# CHECK-2003: No soft delete mechanism
# ==============================================================================

# _check_2003_soft_delete PROJECT_PATH
#   Check whether the project uses soft delete. If hard DELETE is found and
#   no soft delete pattern exists, flag it for review.
_check_2003_soft_delete() {
    local project_path="$1"

    # 1. Check for soft-delete fields in entity classes
    local entity_files
    entity_files=$(_find_entity_files "$project_path")

    local has_soft_delete_field=false
    local has_table_logic_annotation=false

    if [[ -n "$entity_files" ]]; then
        while IFS= read -r entity_file; do
            [[ -z "$entity_file" ]] && continue
            [[ ! -f "$entity_file" ]] && continue

            # Check for soft-delete field names
            if grep -qEi '\b(deleted|isDeleted|is_deleted|deleteFlag|delete_flag|removedAt|removed)\b' "$entity_file" 2>/dev/null; then
                has_soft_delete_field=true
            fi

            # Check for @TableLogic (MyBatis-Plus soft delete annotation)
            if grep -q '@TableLogic' "$entity_file" 2>/dev/null; then
                has_table_logic_annotation=true
            fi

            # Early exit if both found
            if [[ "$has_soft_delete_field" == "true" && "$has_table_logic_annotation" == "true" ]]; then
                break
            fi
        done <<< "$entity_files"
    fi

    # 2. Check for hard DELETE in mapper XMLs
    local mapper_files
    mapper_files=$(find_xml_mappers "$project_path")

    local hard_delete_files=""

    if [[ -n "$mapper_files" ]]; then
        while IFS= read -r mapper_file; do
            [[ -z "$mapper_file" ]] && continue
            [[ ! -f "$mapper_file" ]] && continue

            # Look for DELETE FROM statements (not inside comments)
            local delete_hits
            delete_hits=$(awk '
                BEGIN { in_comment = 0 }
                {
                    line = $0
                    result = ""
                    while (length(line) > 0) {
                        if (in_comment) {
                            pos = index(line, "-->" )
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
                    if (toupper(result) ~ /DELETE[[:space:]]+FROM/) {
                        print NR ":" result
                    }
                }
            ' "$mapper_file" 2>/dev/null) || true

            if [[ -n "$delete_hits" ]]; then
                local rel_path="${mapper_file#"$project_path"/}"
                hard_delete_files="${hard_delete_files}${hard_delete_files:+, }${rel_path}"

                # If no soft delete mechanism found, report each DELETE FROM occurrence
                if [[ "$has_soft_delete_field" == "false" && "$has_table_logic_annotation" == "false" ]]; then
                    while IFS= read -r hit; do
                        [[ -z "$hit" ]] && continue

                        local line_num="${hit%%:*}"
                        local line_content="${hit#*:}"
                        line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                        local context_json
                        context_json=$(printf '{"file":"%s","line":%s,"code":"%s","hasSoftDeleteField":%s,"hasTableLogic":%s,"reason":"Hard DELETE found without any soft-delete mechanism in the project. Consider using a logical delete flag (e.g., is_deleted column with @TableLogic) instead of physical deletes."}' \
                            "$(json_escape "$rel_path")" \
                            "$line_num" \
                            "$(json_escape "$line_content")" \
                            "$has_soft_delete_field" \
                            "$has_table_logic_annotation")

                        json_finding_with_context \
                            "CHECK-2003" \
                            "needs_ai_review" \
                            "MAJOR" \
                            "$_DS_DIM_NUMBER" \
                            "$_DS_DIM_NAME" \
                            "Hard DELETE used without soft-delete mechanism" \
                            "$rel_path" \
                            "$context_json"
                    done <<< "$delete_hits"
                fi
            fi
        done <<< "$mapper_files"
    fi

    # 3. Also check Java files for hard DELETE via annotations or native queries
    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -n "$java_files" && "$has_soft_delete_field" == "false" && "$has_table_logic_annotation" == "false" ]]; then
        while IFS= read -r java_file; do
            [[ -z "$java_file" ]] && continue
            [[ ! -f "$java_file" ]] && continue

            # Check for @Delete annotation with DELETE FROM, or deleteById patterns
            # that suggest hard delete without soft delete in place
            local delete_hits
            delete_hits=$(grep -n -iE 'DELETE[[:space:]]+FROM' "$java_file" 2>/dev/null) || true

            if [[ -n "$delete_hits" ]]; then
                local rel_path="${java_file#"$project_path"/}"

                while IFS= read -r hit; do
                    [[ -z "$hit" ]] && continue

                    local line_num="${hit%%:*}"
                    local line_content="${hit#*:}"
                    line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                    local context_json
                    context_json=$(printf '{"file":"%s","line":%s,"code":"%s","hasSoftDeleteField":%s,"hasTableLogic":%s,"reason":"Hard DELETE FROM found in Java code without soft-delete mechanism in the project."}' \
                        "$(json_escape "$rel_path")" \
                        "$line_num" \
                        "$(json_escape "$line_content")" \
                        "$has_soft_delete_field" \
                        "$has_table_logic_annotation")

                    json_finding_with_context \
                        "CHECK-2003" \
                        "needs_ai_review" \
                        "MAJOR" \
                        "$_DS_DIM_NUMBER" \
                        "$_DS_DIM_NAME" \
                        "Hard DELETE used in Java code without soft-delete mechanism" \
                        "$rel_path" \
                        "$context_json"
                done <<< "$delete_hits"
            fi
        done <<< "$java_files"
    fi
}

# ==============================================================================
# CHECK-2004: Plaintext password storage
# ==============================================================================

# _check_2004_plaintext_password PROJECT_PATH
#   Search for patterns suggesting plaintext password handling.
_check_2004_plaintext_password() {
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

        # Pattern 1: .setPassword( without encoding nearby
        local set_pw_hits
        set_pw_hits=$(grep -n '\.setPassword(' "$java_file" 2>/dev/null) || true

        if [[ -n "$set_pw_hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"

                # Read surrounding context (5 lines before and after) to check
                # for password encoding/hashing
                local context_start=$((line_num - 5))
                [[ "$context_start" -lt 1 ]] && context_start=1
                local context_end=$((line_num + 5))

                local context
                context=$(sed -n "${context_start},${context_end}p" "$java_file" 2>/dev/null) || true

                # Check if encoding/hashing is present nearby
                if printf '%s' "$context" | grep -qEi 'encode|encrypt|hash|BCrypt|PasswordEncoder|DigestUtils|MessageDigest|SCrypt|Argon|PBKDF' 2>/dev/null; then
                    continue
                fi

                line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                local context_json
                context_json=$(printf '{"file":"%s","line":%s,"code":"%s","reason":".setPassword() called without nearby password encoding/hashing (no encode/encrypt/hash/BCrypt/PasswordEncoder found within ±5 lines). Password may be stored in plaintext."}' \
                    "$(json_escape "$rel_path")" \
                    "$line_num" \
                    "$(json_escape "$line_content")")

                json_finding_with_context \
                    "CHECK-2004" \
                    "needs_ai_review" \
                    "MAJOR" \
                    "$_DS_DIM_NUMBER" \
                    "$_DS_DIM_NAME" \
                    "Possible plaintext password in .setPassword() call" \
                    "$rel_path" \
                    "$context_json"
            done <<< "$set_pw_hits"
        fi

        # Pattern 2: Direct password assignment without encoding
        # e.g., user.password = xxx, this.password = xxx
        local assign_pw_hits
        assign_pw_hits=$(grep -n -E '\bpassword\s*=' "$java_file" 2>/dev/null | \
            grep -v -E '=\s*null\b|==|!=|getPassword|PasswordEncoder|password\s*=\s*""|@' 2>/dev/null) || true

        if [[ -n "$assign_pw_hits" ]]; then
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue

                local line_num="${hit%%:*}"
                local line_content="${hit#*:}"

                # Check surrounding context for encoding
                local context_start=$((line_num - 5))
                [[ "$context_start" -lt 1 ]] && context_start=1
                local context_end=$((line_num + 5))

                local context
                context=$(sed -n "${context_start},${context_end}p" "$java_file" 2>/dev/null) || true

                if printf '%s' "$context" | grep -qEi 'encode|encrypt|hash|BCrypt|PasswordEncoder|DigestUtils|MessageDigest|SCrypt|Argon|PBKDF' 2>/dev/null; then
                    continue
                fi

                line_content=$(printf '%s' "$line_content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                local context_json
                context_json=$(printf '{"file":"%s","line":%s,"code":"%s","reason":"Direct password assignment without nearby encoding/hashing. Verify the password value is properly hashed before storage."}' \
                    "$(json_escape "$rel_path")" \
                    "$line_num" \
                    "$(json_escape "$line_content")")

                json_finding_with_context \
                    "CHECK-2004" \
                    "needs_ai_review" \
                    "MAJOR" \
                    "$_DS_DIM_NUMBER" \
                    "$_DS_DIM_NAME" \
                    "Possible plaintext password assignment" \
                    "$rel_path" \
                    "$context_json"
            done <<< "$assign_pw_hits"
        fi
    done <<< "$java_files"

    # Pattern 3: SQL INSERT with password column and no transformation
    local mapper_files
    mapper_files=$(find_xml_mappers "$project_path")

    if [[ -n "$mapper_files" ]]; then
        while IFS= read -r mapper_file; do
            [[ -z "$mapper_file" ]] && continue
            [[ ! -f "$mapper_file" ]] && continue

            local rel_path="${mapper_file#"$project_path"/}"

            # Find INSERT statements that reference a password column
            local insert_hits
            insert_hits=$(awk '
                BEGIN { IGNORECASE = 1; in_insert = 0; block = ""; start_line = 0 }
                /<insert[[:space:]]/ {
                    in_insert = 1
                    block = $0
                    start_line = NR
                    if ($0 ~ /<\/insert>/) {
                        in_insert = 0
                        if (tolower(block) ~ /password/) {
                            print start_line ":" block
                        }
                        block = ""
                    }
                    next
                }
                in_insert {
                    block = block " " $0
                    if ($0 ~ /<\/insert>/) {
                        in_insert = 0
                        if (tolower(block) ~ /password/) {
                            print start_line ":" block
                        }
                        block = ""
                    }
                }
            ' "$mapper_file" 2>/dev/null) || true

            if [[ -n "$insert_hits" ]]; then
                while IFS= read -r hit; do
                    [[ -z "$hit" ]] && continue

                    local line_num="${hit%%:*}"
                    local block_content="${hit#*:}"

                    # If the INSERT directly maps a password param without any
                    # indication of pre-processing, flag it
                    # This is highly heuristic — the encoding usually happens in
                    # Java code, not in SQL. Flag for AI review.
                    local context_json
                    context_json=$(printf '{"file":"%s","line":%s,"reason":"INSERT statement references password column. Verify that the password value is hashed in the service layer before being passed to the mapper."}' \
                        "$(json_escape "$rel_path")" \
                        "$line_num")

                    json_finding_with_context \
                        "CHECK-2004" \
                        "needs_ai_review" \
                        "MAJOR" \
                        "$_DS_DIM_NUMBER" \
                        "$_DS_DIM_NAME" \
                        "INSERT mapper references password column — verify encoding in service layer" \
                        "$rel_path" \
                        "$context_json"
                done <<< "$insert_hits"
            fi
        done <<< "$mapper_files"
    fi
}

# ==============================================================================
# Public API
# ==============================================================================

# check_data_storage PROJECT_PATH
#   Run all data storage design checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_data_storage() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_data_storage: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-2001: Queries missing ownership filter..."
    _check_2001_xml_mappers "$project_path"
    _check_2001_java_queries "$project_path"

    log_info "Running CHECK-2002: Tables missing timestamp fields..."
    _check_2002_entity_classes "$project_path"
    _check_2002_sql_migrations "$project_path"

    log_info "Running CHECK-2003: No soft delete mechanism..."
    _check_2003_soft_delete "$project_path"

    log_info "Running CHECK-2004: Plaintext password storage..."
    _check_2004_plaintext_password "$project_path"

    log_info "Data storage design checks complete."
}
