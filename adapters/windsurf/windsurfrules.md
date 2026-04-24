# Java Server Architecture Review Rules

## Trigger
When the user asks to review Java/Spring Boot project architecture, code quality, or engineering standards.

Keywords: 架构审查, 设计审查, Java 后端审查, review 后端代码, server arch review, 检查工程质量

## Workflow

1. Run the scanning script:
   ```bash
   bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode {MODE}
   ```

2. Parse the JSON output:
   - `confirmed` findings → include directly in report
   - `needs_ai_review` findings → read related code and make judgment
   - `uncoveredDimensions` → read corresponding rules from `{SKILL_DIR}/references/` and review manually

3. Generate the final report in Markdown format with health score (0-100).

## Modes
- full: All 19 dimensions
- pr: Only changed files (default for PR reviews)
- focus: Specific dimensions (e.g., --dimensions "sql-injection,security")
- quick: BLOCKER only
