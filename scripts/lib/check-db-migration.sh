#!/usr/bin/env bash
# ==============================================================================
# check-db-migration.sh - Database Migration Management checks
#
# Checks:
#   CHECK-2301 [BLOCKER] Schema changes with no versioned migration management
#   CHECK-2305 [MAJOR]   Migration files not tracked in Git
#
# Provides: check_db_migration PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding, find_pom_files, find_gradle_files,
#           find_yaml_configs, find_properties_configs
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _DB_MIG_DIM_NUMBER=23
readonly _DB_MIG_DIM_NAME="数据库迁移管理"

# ==============================================================================
# Internal helpers
# ==============================================================================

# _has_db_dependency PROJECT_PATH
#   Check whether the project declares any database-related dependency
#   (JDBC, MyBatis, JPA/Hibernate, R2DBC) in Maven or Gradle build files.
#   Returns 0 if a database dependency is found, 1 otherwise.
_has_db_dependency() {
    local project_path="$1"

    # --- Maven pom.xml ---
    local pom_files
    pom_files=$(find_pom_files "$project_path")

    if [[ -n "$pom_files" ]]; then
        while IFS= read -r pom; do
            [[ -z "$pom" || ! -f "$pom" ]] && continue
            if grep -qE '(spring-boot-starter-jdbc|spring-boot-starter-data-jpa|mybatis|mysql-connector|postgresql|mariadb-java-client|ojdbc|h2database|hsqldb|sqlite-jdbc|mssql-jdbc|spring-boot-starter-data-r2dbc|r2dbc-|druid|HikariCP|commons-dbcp|spring-jdbc)' "$pom" 2>/dev/null; then
                return 0
            fi
        done <<< "$pom_files"
    fi

    # --- Gradle build files ---
    local gradle_files
    gradle_files=$(find_gradle_files "$project_path")

    if [[ -n "$gradle_files" ]]; then
        while IFS= read -r gf; do
            [[ -z "$gf" || ! -f "$gf" ]] && continue
            if grep -qE '(spring-boot-starter-jdbc|spring-boot-starter-data-jpa|mybatis|mysql-connector|postgresql|mariadb-java-client|ojdbc|h2database|hsqldb|sqlite-jdbc|mssql-jdbc|spring-boot-starter-data-r2dbc|r2dbc-|druid|HikariCP|commons-dbcp|spring-jdbc)' "$gf" 2>/dev/null; then
                return 0
            fi
        done <<< "$gradle_files"
    fi

    return 1
}

# _has_migration_dependency PROJECT_PATH
#   Check whether the project declares a Flyway or Liquibase dependency in
#   Maven or Gradle build files.
#   Returns 0 if found, 1 otherwise.
_has_migration_dependency() {
    local project_path="$1"

    local pom_files
    pom_files=$(find_pom_files "$project_path")

    if [[ -n "$pom_files" ]]; then
        while IFS= read -r pom; do
            [[ -z "$pom" || ! -f "$pom" ]] && continue
            if grep -qEi '(flyway|liquibase)' "$pom" 2>/dev/null; then
                return 0
            fi
        done <<< "$pom_files"
    fi

    local gradle_files
    gradle_files=$(find_gradle_files "$project_path")

    if [[ -n "$gradle_files" ]]; then
        while IFS= read -r gf; do
            [[ -z "$gf" || ! -f "$gf" ]] && continue
            if grep -qEi '(flyway|liquibase)' "$gf" 2>/dev/null; then
                return 0
            fi
        done <<< "$gradle_files"
    fi

    return 1
}

# _has_migration_config PROJECT_PATH
#   Check whether Flyway or Liquibase configuration exists in Spring
#   application YAML or properties files.
#   Returns 0 if found, 1 otherwise.
_has_migration_config() {
    local project_path="$1"

    local yaml_files
    yaml_files=$(find_yaml_configs "$project_path")

    if [[ -n "$yaml_files" ]]; then
        while IFS= read -r yf; do
            [[ -z "$yf" || ! -f "$yf" ]] && continue
            if grep -qEi '(flyway|liquibase)' "$yf" 2>/dev/null; then
                return 0
            fi
        done <<< "$yaml_files"
    fi

    local props_files
    props_files=$(find_properties_configs "$project_path")

    if [[ -n "$props_files" ]]; then
        while IFS= read -r pf; do
            [[ -z "$pf" || ! -f "$pf" ]] && continue
            if grep -qEi '(flyway|liquibase)' "$pf" 2>/dev/null; then
                return 0
            fi
        done <<< "$props_files"
    fi

    return 1
}

# _find_migration_dirs PROJECT_PATH
#   Locate well-known migration directories within the project.
#   Prints one directory path per line to stdout.
_find_migration_dirs() {
    local project_path="$1"

    find "$project_path" -type d \( \
        -path '*/db/migration' -o \
        -path '*/db/changelog' -o \
        -path '*/flyway' -o \
        -path '*/liquibase' \
    \) \
        ! -path '*/target/*' \
        ! -path '*/build/*' \
        ! -path '*/.gradle/*' \
        ! -path '*/node_modules/*' \
        2>/dev/null || true
}

# ==============================================================================
# CHECK-2301: Schema changes with no versioned migration management
# ==============================================================================

_check_2301_no_versioned_migration() {
    local project_path="$1"

    # Step 1: Does the project use a database at all?
    if ! _has_db_dependency "$project_path"; then
        log_info "CHECK-2301: No database dependency detected – skipping."
        return
    fi

    # Step 2: Check for migration tool dependency
    if _has_migration_dependency "$project_path"; then
        log_info "CHECK-2301: Migration tool dependency found."
        return
    fi

    # Step 3: Check for migration config in application config files
    if _has_migration_config "$project_path"; then
        log_info "CHECK-2301: Migration tool config found in application config."
        return
    fi

    # Step 4: Check for well-known migration directories
    local migration_dirs
    migration_dirs=$(_find_migration_dirs "$project_path")

    if [[ -n "$migration_dirs" ]]; then
        log_info "CHECK-2301: Migration directories found."
        return
    fi

    # None of the above – flag it
    # Try to identify one representative build file for the finding
    local build_file=""
    local pom_files
    pom_files=$(find_pom_files "$project_path")
    if [[ -n "$pom_files" ]]; then
        build_file=$(printf '%s' "$pom_files" | head -1)
    else
        local gradle_files
        gradle_files=$(find_gradle_files "$project_path")
        if [[ -n "$gradle_files" ]]; then
            build_file=$(printf '%s' "$gradle_files" | head -1)
        fi
    fi

    local rel_path=""
    if [[ -n "$build_file" ]]; then
        rel_path="${build_file#"$project_path"/}"
    fi

    json_finding \
        "CHECK-2301" \
        "confirmed" \
        "BLOCKER" \
        "$_DB_MIG_DIM_NUMBER" \
        "$_DB_MIG_DIM_NAME" \
        "Project uses a database but has no versioned migration tool (Flyway/Liquibase)" \
        "$rel_path" \
        "" \
        "" \
        "Add Flyway or Liquibase to manage database schema changes. Use versioned migration scripts (e.g. V1__init.sql) instead of ad-hoc DDL execution. This ensures repeatable, auditable schema evolution across environments."
}

# ==============================================================================
# CHECK-2305: Migration files not tracked in Git
# ==============================================================================

_check_2305_migration_not_in_git() {
    local project_path="$1"

    local migration_dirs
    migration_dirs=$(_find_migration_dirs "$project_path")

    if [[ -z "$migration_dirs" ]]; then
        return
    fi

    # Check .gitignore files for patterns that would exclude migration dirs
    local gitignore_files
    gitignore_files=$(find "$project_path" -name '.gitignore' \
        ! -path '*/target/*' \
        ! -path '*/build/*' \
        ! -path '*/.gradle/*' \
        ! -path '*/node_modules/*' \
        2>/dev/null) || true

    while IFS= read -r mig_dir; do
        [[ -z "$mig_dir" || ! -d "$mig_dir" ]] && continue

        local rel_mig_dir="${mig_dir#"$project_path"/}"

        # --- Sub-check A: Migration directory exists but contains no files ---
        local file_count
        file_count=$(find "$mig_dir" -type f \
            \( -name '*.sql' -o -name '*.xml' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) \
            2>/dev/null | wc -l | tr -d '[:space:]')

        if [[ "$file_count" -eq 0 ]]; then
            json_finding \
                "CHECK-2305" \
                "confirmed" \
                "MAJOR" \
                "$_DB_MIG_DIM_NUMBER" \
                "$_DB_MIG_DIM_NAME" \
                "Migration directory exists but contains no migration files" \
                "$rel_mig_dir" \
                "" \
                "" \
                "Add versioned migration files (e.g. V1__init_schema.sql) to the migration directory. An empty migration directory suggests migrations may be managed outside version control."
            continue
        fi

        # --- Sub-check B: .gitignore excludes the migration directory ---
        if [[ -n "$gitignore_files" ]]; then
            while IFS= read -r gi_file; do
                [[ -z "$gi_file" || ! -f "$gi_file" ]] && continue

                # Extract the directory the .gitignore lives in to resolve relative patterns
                local gi_dir
                gi_dir=$(dirname "$gi_file")
                local rel_gi="${gi_file#"$project_path"/}"

                # Check for patterns that could match the migration directory:
                #   - Exact directory name (e.g. db/migration)
                #   - Glob that covers it (e.g. db/migration/*)
                #   - Parent wildcard (e.g. **/migration)
                # We keep it simple: check if any line, after trimming, is a
                # prefix/match for the migration dir path relative to the
                # .gitignore location.
                local rel_to_gi="${mig_dir#"$gi_dir"/}"

                # Quick grep: look for lines that could plausibly match
                if grep -qE "^[[:space:]]*(${rel_to_gi}|${rel_to_gi}/|\*\*/${rel_to_gi##*/})" "$gi_file" 2>/dev/null; then
                    json_finding \
                        "CHECK-2305" \
                        "confirmed" \
                        "MAJOR" \
                        "$_DB_MIG_DIM_NUMBER" \
                        "$_DB_MIG_DIM_NAME" \
                        "Migration directory is excluded by .gitignore" \
                        "$rel_gi" \
                        "" \
                        ".gitignore pattern matches: $rel_mig_dir" \
                        "Remove the .gitignore rule that excludes the migration directory. Migration scripts must be version-controlled to ensure consistent schema across all environments."
                fi
            done <<< "$gitignore_files"
        fi
    done <<< "$migration_dirs"
}

# ==============================================================================
# Public API
# ==============================================================================

# check_db_migration PROJECT_PATH
#   Run all database migration management checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_db_migration() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_db_migration: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-2301: Schema changes with no versioned migration management..."
    _check_2301_no_versioned_migration "$project_path"

    log_info "Running CHECK-2305: Migration files not tracked in Git..."
    _check_2305_migration_not_in_git "$project_path"

    log_info "Database migration checks complete."
}
