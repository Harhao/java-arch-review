# Java Server Architecture Review Skill

## Skill Registration

This project includes the `java-arch-review` skill for reviewing Java/Spring Boot server architectures.

## Activation

Activate this skill when the user requests:
- Java project architecture review (架构审查)
- Backend code review (后端审查/后端 CR)
- Engineering quality check (工程质量检查)
- Server architecture review

## Usage

### Step 1: Run Scanner
```bash
bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode {MODE}
```

Modes: full (default) | pr | focus | quick

### Step 2: Analyze Results
The script outputs JSON with:
- `findings[].type == "confirmed"` → deterministic, include directly
- `findings[].type == "needs_ai_review"` → read code, apply judgment
- `uncoveredDimensions` → review using rules in `{SKILL_DIR}/references/`

### Step 3: Generate Report
- Merge script results + your analysis
- Calculate health score: 100 - (BLOCKER * 5) - (MAJOR * 2) - (MINOR * 1)
- Output Markdown report grouped by severity

## Reference Files
Located at `{SKILL_DIR}/references/`:
- coding-standards.md, database-index.md, sql-injection.md
- config-logging.md, error-handling.md, code-layering.md
- security-auth.md, api-design.md, rate-limiting.md
- quality-testing.md, data-storage.md, db-migration.md
