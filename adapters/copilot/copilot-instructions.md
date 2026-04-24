# Java Architecture Review Instructions

When asked to review Java/Spring Boot project architecture or code quality:

1. Execute the architecture review script:
   ```bash
   bash {SKILL_DIR}/scripts/arch-review.sh --project . --mode full
   ```

2. The script outputs structured JSON with findings categorized as:
   - `confirmed`: Deterministic issues found by static analysis
   - `needs_ai_review`: Suspicious patterns requiring your judgment

3. For `needs_ai_review` items, read the source code and reference rules at `{SKILL_DIR}/references/` to make informed decisions.

4. For dimensions not covered by the script (listed in `uncoveredDimensions`), perform manual review following the rules in the references directory.

5. Generate a comprehensive review report with:
   - Health score (0-100, deducting 5/2/1 per BLOCKER/MAJOR/MINOR)
   - Findings grouped by severity (BLOCKER → MAJOR → MINOR)
   - Actionable fix suggestions for each finding

Trigger keywords: architecture review, Java review, backend review, code quality check, 架构审查, 后端审查
