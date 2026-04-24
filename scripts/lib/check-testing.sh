#!/usr/bin/env bash
# ==============================================================================
# check-testing.sh - Testing & Documentation checks
#
# Checks:
#   CHECK-1201 [MAJOR]   Missing README
#   CHECK-1202 [MAJOR]   Missing API documentation (Swagger/OpenAPI)
#   CHECK-1301 [BLOCKER] Core business logic missing unit tests
#   CHECK-1302 [MAJOR]   Low test coverage indicator
#   CHECK-1303 [MAJOR]   CI pipeline missing test gates
#
# Provides: check_testing PROJECT_PATH
# Outputs:  JSON finding objects to stdout (one per line)
#
# Requires: common.sh for json_finding, json_finding_with_context,
#           find_java_files, find_test_files, find_pom_files, find_gradle_files
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Dimension constants
readonly _TESTING_DIM_DOC_NUMBER=12
readonly _TESTING_DIM_DOC_NAME="文档沉淀"
readonly _TESTING_DIM_TEST_NUMBER=13
readonly _TESTING_DIM_TEST_NAME="测试保障"

# ==============================================================================
# CHECK-1201: Missing README
# ==============================================================================

_check_1201_missing_readme() {
    local project_path="$1"

    if [[ -f "$project_path/README.md" ]] || [[ -f "$project_path/README" ]] \
        || [[ -f "$project_path/readme.md" ]] || [[ -f "$project_path/Readme.md" ]]; then
        return
    fi

    json_finding \
        "CHECK-1201" \
        "confirmed" \
        "MAJOR" \
        "$_TESTING_DIM_DOC_NUMBER" \
        "$_TESTING_DIM_DOC_NAME" \
        "Project is missing a README file" \
        "." \
        "" \
        "" \
        "Add a README.md to the project root with: project overview, setup instructions, build commands, architecture notes, and contribution guidelines."
}

# ==============================================================================
# CHECK-1202: Missing API documentation (Swagger/OpenAPI)
# ==============================================================================

_check_1202_missing_api_docs() {
    local project_path="$1"

    # 1) Check for springdoc-openapi or springfox in build files
    local has_dependency=false

    # Check pom.xml files
    local pom_files
    pom_files=$(find_pom_files "$project_path")
    if [[ -n "$pom_files" ]]; then
        while IFS= read -r pom_file; do
            [[ -z "$pom_file" ]] && continue
            [[ ! -f "$pom_file" ]] && continue
            if grep -qE 'springdoc-openapi|springfox|swagger' "$pom_file" 2>/dev/null; then
                has_dependency=true
                break
            fi
        done <<< "$pom_files"
    fi

    # Check build.gradle files if not found in pom.xml
    if [[ "$has_dependency" == false ]]; then
        local gradle_files
        gradle_files=$(find_gradle_files "$project_path")
        if [[ -n "$gradle_files" ]]; then
            while IFS= read -r gradle_file; do
                [[ -z "$gradle_file" ]] && continue
                [[ ! -f "$gradle_file" ]] && continue
                if grep -qE 'springdoc-openapi|springfox|swagger' "$gradle_file" 2>/dev/null; then
                    has_dependency=true
                    break
                fi
            done <<< "$gradle_files"
        fi
    fi

    # If dependency found, no issue
    if [[ "$has_dependency" == true ]]; then
        return
    fi

    # 2) Check for OpenAPI annotations in Java source files
    local has_annotation=false
    local java_files
    java_files=$(find_java_files "$project_path")
    if [[ -n "$java_files" ]]; then
        # Use a single grep pass across all files for efficiency
        if printf '%s' "$java_files" | xargs grep -lE '@(OpenAPIDefinition|Api|ApiOperation|Tag|Operation)' 2>/dev/null | head -1 | grep -q .; then
            has_annotation=true
        fi
    fi

    if [[ "$has_annotation" == true ]]; then
        return
    fi

    # 3) Check for swagger/openapi config in application YAML/properties
    local has_config=false

    local yaml_configs
    yaml_configs=$(find_yaml_configs "$project_path")
    if [[ -n "$yaml_configs" ]]; then
        while IFS= read -r config_file; do
            [[ -z "$config_file" ]] && continue
            [[ ! -f "$config_file" ]] && continue
            if grep -qE 'swagger|springdoc|openapi' "$config_file" 2>/dev/null; then
                has_config=true
                break
            fi
        done <<< "$yaml_configs"
    fi

    if [[ "$has_config" == false ]]; then
        local props_configs
        props_configs=$(find_properties_configs "$project_path")
        if [[ -n "$props_configs" ]]; then
            while IFS= read -r config_file; do
                [[ -z "$config_file" ]] && continue
                [[ ! -f "$config_file" ]] && continue
                if grep -qE 'swagger|springdoc|openapi' "$config_file" 2>/dev/null; then
                    has_config=true
                    break
                fi
            done <<< "$props_configs"
        fi
    fi

    if [[ "$has_config" == true ]]; then
        return
    fi

    # None found — flag it
    json_finding \
        "CHECK-1202" \
        "confirmed" \
        "MAJOR" \
        "$_TESTING_DIM_DOC_NUMBER" \
        "$_TESTING_DIM_DOC_NAME" \
        "No Swagger/OpenAPI documentation setup found" \
        "." \
        "" \
        "" \
        "Add springdoc-openapi dependency (org.springdoc:springdoc-openapi-starter-webmvc-ui) and annotate controllers with @Tag/@Operation, or add springfox for Swagger 2 support."
}

# ==============================================================================
# CHECK-1301: Core business logic missing unit tests
# ==============================================================================

_check_1301_missing_service_tests() {
    local project_path="$1"

    # Collect all test file basenames (without Test/Tests suffix) for fast lookup
    local test_files
    test_files=$(find_test_files "$project_path")

    # Build an associative-style lookup of test basenames
    # We store them in a temp file for portable grep-based lookup
    local test_names_file
    test_names_file=$(mktemp "${TMPDIR:-/tmp}/check1301_tests.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -f '$test_names_file'" RETURN

    if [[ -n "$test_files" ]]; then
        while IFS= read -r tf; do
            [[ -z "$tf" ]] && continue
            local basename
            basename=$(basename "$tf" .java)
            # Strip common test suffixes to get the source class name
            local source_name
            source_name="${basename%Tests}"
            source_name="${source_name%Test}"
            source_name="${source_name%IT}"
            source_name="${source_name%Spec}"
            printf '%s\n' "$source_name"
        done <<< "$test_files"
    fi | sort -u > "$test_names_file"

    # Find Service classes in main source directories
    local java_files
    java_files=$(find_java_files "$project_path")

    if [[ -z "$java_files" ]]; then
        return
    fi

    local missing_count=0
    local missing_list=""

    while IFS= read -r java_file; do
        [[ -z "$java_file" ]] && continue
        [[ ! -f "$java_file" ]] && continue

        # Only consider files under src/main/java
        case "$java_file" in
            */src/main/java/*) ;;
            *) continue ;;
        esac

        # Check if this is a Service class (by annotation or naming convention)
        local basename
        basename=$(basename "$java_file" .java)

        # Must be a Service: check @Service annotation or *Service/*ServiceImpl naming
        local is_service_file=false
        if is_service "$java_file"; then
            is_service_file=true
        elif [[ "$basename" == *Service || "$basename" == *ServiceImpl ]]; then
            is_service_file=true
        fi

        if [[ "$is_service_file" == false ]]; then
            continue
        fi

        # Check if a corresponding test exists
        # For FooServiceImpl, also check FooService as the test base name
        local base_for_test="$basename"
        local alt_base_for_test=""
        if [[ "$basename" == *ServiceImpl ]]; then
            alt_base_for_test="${basename%Impl}"
        fi

        local has_test=false
        if grep -qxF "$base_for_test" "$test_names_file" 2>/dev/null; then
            has_test=true
        elif [[ -n "$alt_base_for_test" ]] && grep -qxF "$alt_base_for_test" "$test_names_file" 2>/dev/null; then
            has_test=true
        fi

        if [[ "$has_test" == false ]]; then
            local rel_path="${java_file#"$project_path"/}"
            missing_count=$((missing_count + 1))

            if [[ -n "$missing_list" ]]; then
                missing_list="$missing_list, $basename"
            else
                missing_list="$basename"
            fi

            json_finding \
                "CHECK-1301" \
                "confirmed" \
                "BLOCKER" \
                "$_TESTING_DIM_TEST_NUMBER" \
                "$_TESTING_DIM_TEST_NAME" \
                "Service class '$basename' has no corresponding unit test" \
                "$rel_path" \
                "" \
                "" \
                "Create ${basename}Test.java under src/test/java with the matching package structure. Cover core business logic, edge cases, and error paths."
        fi
    done <<< "$java_files"

    if [[ $missing_count -gt 0 ]]; then
        log_info "CHECK-1301: Found $missing_count service class(es) without tests: $missing_list"
    fi
}

# ==============================================================================
# CHECK-1302: Low test coverage indicator
# ==============================================================================

_check_1302_low_coverage_indicator() {
    local project_path="$1"

    # Count source files under src/main/java
    local source_count=0
    local java_files
    java_files=$(find "$project_path" -type f -name '*.java' -path '*/src/main/java/*' \
        2>/dev/null) || true

    if [[ -n "$java_files" ]]; then
        source_count=$(printf '%s\n' "$java_files" | grep -c . 2>/dev/null) || source_count=0
    fi

    # If no source files, nothing to check
    if [[ "$source_count" -eq 0 ]]; then
        return
    fi

    # Count test files under src/test/java
    local test_count=0
    local test_java_files
    test_java_files=$(find "$project_path" -type f -name '*.java' -path '*/src/test/java/*' \
        2>/dev/null) || true

    if [[ -n "$test_java_files" ]]; then
        test_count=$(printf '%s\n' "$test_java_files" | grep -c . 2>/dev/null) || test_count=0
    fi

    # Calculate ratio (integer arithmetic: multiply by 100 to avoid floating point)
    local ratio_pct=$(( (test_count * 100) / source_count ))

    if [[ "$ratio_pct" -lt 30 ]]; then
        local context_json
        context_json=$(printf '{"sourceFiles":%d,"testFiles":%d,"ratioPercent":%d}' \
            "$source_count" "$test_count" "$ratio_pct")

        json_finding_with_context \
            "CHECK-1302" \
            "needs_ai_review" \
            "MAJOR" \
            "$_TESTING_DIM_TEST_NUMBER" \
            "$_TESTING_DIM_TEST_NAME" \
            "Low test coverage: only ${ratio_pct}% of source files have corresponding tests (${test_count}/${source_count})" \
            "." \
            "$context_json"
    fi
}

# ==============================================================================
# CHECK-1303: CI pipeline missing test gates
# ==============================================================================

_check_1303_ci_missing_test_gates() {
    local project_path="$1"

    # Collect CI config files
    local ci_files=""

    # GitHub Actions
    local gh_workflows
    gh_workflows=$(find "$project_path/.github/workflows" -type f -name '*.yml' -o -name '*.yaml' 2>/dev/null) || true
    if [[ -n "$gh_workflows" ]]; then
        ci_files="$gh_workflows"
    fi

    # Jenkinsfile
    if [[ -f "$project_path/Jenkinsfile" ]]; then
        if [[ -n "$ci_files" ]]; then
            ci_files="$ci_files"$'\n'"$project_path/Jenkinsfile"
        else
            ci_files="$project_path/Jenkinsfile"
        fi
    fi

    # GitLab CI
    if [[ -f "$project_path/.gitlab-ci.yml" ]]; then
        if [[ -n "$ci_files" ]]; then
            ci_files="$ci_files"$'\n'"$project_path/.gitlab-ci.yml"
        else
            ci_files="$project_path/.gitlab-ci.yml"
        fi
    fi

    # CircleCI
    if [[ -f "$project_path/.circleci/config.yml" ]]; then
        if [[ -n "$ci_files" ]]; then
            ci_files="$ci_files"$'\n'"$project_path/.circleci/config.yml"
        else
            ci_files="$project_path/.circleci/config.yml"
        fi
    fi

    # No CI config at all
    if [[ -z "$ci_files" ]]; then
        json_finding \
            "CHECK-1303" \
            "confirmed" \
            "MAJOR" \
            "$_TESTING_DIM_TEST_NUMBER" \
            "$_TESTING_DIM_TEST_NAME" \
            "No CI pipeline configuration found" \
            "." \
            "" \
            "" \
            "Add a CI configuration (e.g. .github/workflows/ci.yml, Jenkinsfile, or .gitlab-ci.yml) with test execution steps to ensure automated testing on every push/PR."
        return
    fi

    # CI config exists — check if it contains test/verify commands
    local has_test_gate=false
    while IFS= read -r ci_file; do
        [[ -z "$ci_file" ]] && continue
        [[ ! -f "$ci_file" ]] && continue

        # Look for common test execution patterns:
        #   mvn test, mvn verify, gradle test, ./gradlew test, npm test,
        #   pytest, go test, make test, sbt test, etc.
        if grep -qEi '(mvn\s+(.*\s+)?test|mvn\s+(.*\s+)?verify|gradle\w*\s+test|./gradlew\s+test|npm\s+test|pytest|go\s+test|make\s+test|sbt\s+test|maven-surefire|maven-failsafe)' "$ci_file" 2>/dev/null; then
            has_test_gate=true
            break
        fi

        # Also check for generic "test" step/stage names in YAML CI configs
        if grep -qEi '^\s*(- )?(name|stage|step):\s*.*test' "$ci_file" 2>/dev/null; then
            has_test_gate=true
            break
        fi
    done <<< "$ci_files"

    if [[ "$has_test_gate" == false ]]; then
        # Report against the first CI file found
        local first_ci_file
        first_ci_file=$(printf '%s\n' "$ci_files" | head -1)
        local rel_path="${first_ci_file#"$project_path"/}"

        json_finding \
            "CHECK-1303" \
            "confirmed" \
            "MAJOR" \
            "$_TESTING_DIM_TEST_NUMBER" \
            "$_TESTING_DIM_TEST_NAME" \
            "CI pipeline exists but has no test execution step" \
            "$rel_path" \
            "" \
            "" \
            "Add a test execution step to your CI pipeline (e.g. 'mvn verify', 'gradle test') to enforce automated testing as a quality gate before merge."
    fi
}

# ==============================================================================
# Public API
# ==============================================================================

# check_testing PROJECT_PATH
#   Run all testing & documentation checks against the given project.
#   Outputs JSON finding objects to stdout (one per line).
check_testing() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_testing: invalid project path: $1"
        return 1
    }

    log_info "Running CHECK-1201: Missing README..."
    _check_1201_missing_readme "$project_path"

    log_info "Running CHECK-1202: Missing API documentation..."
    _check_1202_missing_api_docs "$project_path"

    log_info "Running CHECK-1301: Core business logic missing unit tests..."
    _check_1301_missing_service_tests "$project_path"

    log_info "Running CHECK-1302: Low test coverage indicator..."
    _check_1302_low_coverage_indicator "$project_path"

    log_info "Running CHECK-1303: CI pipeline missing test gates..."
    _check_1303_ci_missing_test_gates "$project_path"

    log_info "Testing & documentation checks complete."
}
