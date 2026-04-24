#!/usr/bin/env bash
# ==============================================================================
# check-code-layering.sh - Code Layering checks (CHECK-0601, CHECK-0602, CHECK-0604)
#
# Validates that the project follows proper layered architecture:
#   - Controllers should not contain business logic or access DAO/Repository directly
#   - Services should not use HTTP semantics (Servlet API, ResponseEntity)
#   - Controllers should not expose domain/entity objects directly
#
# Provides: check_code_layering PROJECT_PATH
# Outputs:  JSON findings to stdout (one per line)
#
# Requires: common.sh for find_java_files, is_controller, is_service,
#           json_finding, json_finding_with_context, log_info
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ==============================================================================
# Dimension constants
# ==============================================================================
_CL_DIMENSION=6
_CL_DIM_NAME="代码分层"

# ==============================================================================
# CHECK-0601 [BLOCKER] - Controller containing business logic
#
# Controllers should delegate to the Service layer. They must NOT:
#   - Inject DAO/Mapper/Repository beans directly
#   - Carry @Transactional annotations (transactions belong in the Service layer)
# ==============================================================================
_check_0601_controller_business_logic() {
    local project_path="$1"
    log_info "CHECK-0601: Scanning controllers for business logic leakage..."

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        is_controller "$file" || continue

        local rel_path="${file#"$project_path"/}"

        # --- Sub-check A: Direct DAO/Mapper/Repository injection ---------------
        # Look for field injection patterns:
        #   @Autowired/@Resource + field type containing Mapper/Dao/Repository
        #   (but not *Service*)
        #
        # We match lines like:
        #   @Autowired private UserMapper userMapper;
        #   @Resource  private OrderDao   orderDao;
        #   private final UserRepository userRepo;   (constructor injection)
        #
        # Strategy: scan for variable declarations whose type name ends with
        # Mapper, Dao, or Repository (case-sensitive, standard Java naming).
        local dao_lines
        dao_lines=$(grep -nE '(private|protected|public)\s+\S*(Mapper|Dao|Repository)\s+\S+' "$file" 2>/dev/null || true)

        if [[ -n "$dao_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                # Trim leading/trailing whitespace
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0601" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Controller directly injects DAO/Mapper/Repository — should delegate to Service layer" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Move data-access logic into a @Service class and inject the Service into the Controller instead."
            done <<< "$dao_lines"
        fi

        # --- Sub-check B: @Transactional in Controller -------------------------
        local txn_lines
        txn_lines=$(grep -nE '@Transactional' "$file" 2>/dev/null || true)

        if [[ -n "$txn_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0601" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Controller uses @Transactional — transaction management should be in the Service layer" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Move the transactional logic into a @Service method and call it from the Controller."
            done <<< "$txn_lines"
        fi

    done < <(find_java_files "$project_path")
}

# ==============================================================================
# CHECK-0602 [BLOCKER] - Service layer using HTTP semantics
#
# Service classes should be transport-agnostic. They must NOT:
#   - Import javax.servlet.* / jakarta.servlet.*
#   - Reference HttpServletRequest, HttpServletResponse, HttpSession
#   - Return or import org.springframework.http.ResponseEntity
# ==============================================================================
_check_0602_service_http_semantics() {
    local project_path="$1"
    log_info "CHECK-0602: Scanning services for HTTP semantics leakage..."

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        is_service "$file" || continue

        local rel_path="${file#"$project_path"/}"

        # --- Sub-check A: Servlet API imports ----------------------------------
        local servlet_lines
        servlet_lines=$(grep -nE 'import\s+(javax|jakarta)\.servlet\.' "$file" 2>/dev/null || true)

        if [[ -n "$servlet_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0602" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Service imports Servlet API — service layer should be transport-agnostic" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Extract HTTP-specific data in the Controller and pass plain values/DTOs to the Service."
            done <<< "$servlet_lines"
        fi

        # --- Sub-check B: Direct use of HTTP types -----------------------------
        # Scan for HttpServletRequest, HttpServletResponse, HttpSession as
        # parameter types or variable declarations (not just imports).
        local http_type_lines
        http_type_lines=$(grep -nE '(HttpServletRequest|HttpServletResponse|HttpSession)' "$file" 2>/dev/null || true)
        # Exclude import lines already caught by sub-check A.
        # grep -n output is "NUM:content", so match the prefix before 'import'.
        http_type_lines=$(printf '%s' "$http_type_lines" | grep -vE '^[0-9]+:[[:space:]]*import[[:space:]]' 2>/dev/null || true)

        if [[ -n "$http_type_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0602" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Service references HTTP type directly — decouple from Servlet API" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Pass the required data as method parameters or a DTO instead of the raw Servlet object."
            done <<< "$http_type_lines"
        fi

        # --- Sub-check C: ResponseEntity usage ---------------------------------
        # Check imports first
        local resp_import_lines
        resp_import_lines=$(grep -nE 'import\s+org\.springframework\.http\.ResponseEntity' "$file" 2>/dev/null || true)

        if [[ -n "$resp_import_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0602" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Service imports ResponseEntity — HTTP response construction belongs in the Controller" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Return a domain object or DTO from the Service; let the Controller wrap it in ResponseEntity."
            done <<< "$resp_import_lines"
        fi

        # Check for ResponseEntity return types (not in import lines)
        local resp_type_lines
        resp_type_lines=$(grep -nE 'ResponseEntity' "$file" 2>/dev/null || true)
        # Exclude import lines already caught by sub-check C import scan.
        resp_type_lines=$(printf '%s' "$resp_type_lines" | grep -vE '^[0-9]+:[[:space:]]*import[[:space:]]' 2>/dev/null || true)

        if [[ -n "$resp_type_lines" ]]; then
            while IFS= read -r match_line; do
                [[ -z "$match_line" ]] && continue
                local line_num="${match_line%%:*}"
                local line_text="${match_line#*:}"
                line_text=$(printf '%s' "$line_text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                json_finding \
                    "CHECK-0602" \
                    "confirmed" \
                    "BLOCKER" \
                    "$_CL_DIMENSION" \
                    "$_CL_DIM_NAME" \
                    "Service uses ResponseEntity — HTTP response type should stay in the Controller layer" \
                    "$rel_path" \
                    "$line_num" \
                    "$line_text" \
                    "Return a domain object or DTO from the Service; let the Controller wrap it in ResponseEntity."
            done <<< "$resp_type_lines"
        fi

    done < <(find_java_files "$project_path")
}

# ==============================================================================
# CHECK-0604 [MINOR] - Domain model misuse (needs_ai_review)
#
# Controllers that import entity/domain/model classes AND expose REST endpoints
# may be returning persistence objects directly in the API response. This leaks
# internal schema details and creates tight coupling. AI review should confirm
# whether the entity is actually returned vs. just referenced.
# ==============================================================================
_check_0604_domain_model_misuse() {
    local project_path="$1"
    log_info "CHECK-0604: Scanning controllers for potential domain model exposure..."

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        is_controller "$file" || continue

        local rel_path="${file#"$project_path"/}"

        # Step 1: Does this controller import from .entity. / .model. / .domain. packages?
        local entity_imports
        entity_imports=$(grep -E 'import\s+\S+\.(entity|model|domain)\.\S+' "$file" 2>/dev/null || true)
        [[ -z "$entity_imports" ]] && continue

        # Step 2: Does it have REST endpoint mappings?
        local has_mappings
        has_mappings=$(grep -E '@(Get|Post|Put|Delete|Patch|Request)Mapping' "$file" 2>/dev/null || true)
        [[ -z "$has_mappings" ]] && continue

        # Collect the imported entity class names for context
        local imported_classes
        imported_classes=$(printf '%s' "$entity_imports" \
            | sed 's/.*import[[:space:]]*//; s/[[:space:]]*;.*//' \
            | tr '\n' ', ' \
            | sed 's/,$//')

        # Build context JSON for AI review
        local esc_imports
        esc_imports=$(json_escape "$imported_classes")
        local context_json
        context_json=$(printf '{"importedEntities":"%s","hint":"Check whether these entity/domain classes are returned directly from controller methods. If so, recommend using a VO/DTO for the API response."}' "$esc_imports")

        json_finding_with_context \
            "CHECK-0604" \
            "needs_ai_review" \
            "MINOR" \
            "$_CL_DIMENSION" \
            "$_CL_DIM_NAME" \
            "Controller may expose domain/entity objects directly in API response" \
            "$rel_path" \
            "$context_json"

    done < <(find_java_files "$project_path")
}

# ==============================================================================
# Public API
# ==============================================================================

# check_code_layering PROJECT_PATH
#   Run all code-layering checks against the given project directory.
#   Outputs JSON findings to stdout (one per line).
check_code_layering() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        log_error "check_code_layering: invalid project path: $1"
        return 1
    }

    log_info "Running code layering checks on: $project_path"

    _check_0601_controller_business_logic "$project_path"
    _check_0602_service_http_semantics "$project_path"
    _check_0604_domain_model_misuse "$project_path"

    log_info "Code layering checks complete."
}
