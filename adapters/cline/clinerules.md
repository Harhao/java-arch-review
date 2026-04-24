# Java Architecture Review

## When to Activate
User asks to review Java/Spring Boot project architecture, code quality, or engineering standards.
Keywords: 架构审查, 设计审查, review, 后端审查, server arch review, 工程质量

## Execution Steps

1. **Run scanner**: `bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode full`
2. **Parse JSON output**: 
   - `confirmed` findings → verified issues, include in report
   - `needs_ai_review` → read source code, make judgment
   - `uncoveredDimensions` → review manually using `{SKILL_DIR}/references/`
3. **Generate Markdown report** with health score (100 - BLOCKER*5 - MAJOR*2 - MINOR*1)

## Available Modes
- `full`: Complete 19-dimension scan
- `pr`: Scan only git-changed files
- `focus --dimensions "x,y"`: Targeted dimensions
- `quick`: BLOCKER severity only
