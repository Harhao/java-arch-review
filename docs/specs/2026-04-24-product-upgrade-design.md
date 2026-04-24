# Java Server Arch Review - 产品化升级设计

## 概述

将 java-arch-review 从纯知识库升级为可执行的 AI 产品：
- **bash 扫描脚本**：确定性静态扫描，输出 JSON 结构化结果
- **多 Agent 适配**：覆盖 Claude Code、Cursor、Windsurf、Copilot、Gemini CLI、Cline、OpenCode、Codex CLI
- **混合审查模式**：脚本确定性扫描(~60%) + AI 深度分析(~40%)

## 脚本架构

```
scripts/
├── arch-review.sh                 # 主入口
├── lib/
│   ├── common.sh                  # 公共函数：JSON 输出、文件遍历
│   ├── project-detector.sh        # 项目探测：Spring Boot/ORM/目录
│   ├── check-sql-injection.sh     # CHECK-0201, 0202
│   ├── check-hardcoded-secrets.sh # CHECK-0301
│   ├── check-config.sh            # CHECK-0302, 0303
│   ├── check-logging.sh           # CHECK-0401~0404
│   ├── check-error-handling.sh    # CHECK-0501, 0502
│   ├── check-code-layering.sh     # CHECK-0601, 0602, 0604
│   ├── check-dry.sh               # CHECK-0701, 0702
│   ├── check-api-validation.sh    # CHECK-1001~1003
│   ├── check-testing.sh           # CHECK-1301~1303, 1201, 1202
│   ├── check-data-storage.sh      # CHECK-2001~2004
│   └── check-db-migration.sh      # CHECK-2301, 2305
```

## JSON 输出 Schema

```json
{
  "version": "1.0.0",
  "timestamp": "ISO8601",
  "project": {
    "path": "string",
    "name": "string",
    "springBootVersion": "string|null",
    "orm": "string|null",
    "javaVersion": "string|null",
    "modules": ["string"],
    "sourceFiles": "number",
    "testFiles": "number"
  },
  "scan": {
    "mode": "full|pr|focus|quick",
    "dimensions": ["string"],
    "filesScanned": "number",
    "duration": "string"
  },
  "findings": [{
    "id": "CHECK-XXXX",
    "type": "confirmed|needs_ai_review",
    "severity": "BLOCKER|MAJOR|MINOR",
    "dimension": "number",
    "dimensionName": "string",
    "title": "string",
    "file": "string",
    "line": "number|null",
    "code": "string|null",
    "suggestion": "string|null",
    "context": "object|null"
  }],
  "summary": {
    "total": "number",
    "blocker": "number",
    "major": "number",
    "minor": "number",
    "confirmed": "number",
    "needsAiReview": "number",
    "healthScore": null
  },
  "uncoveredDimensions": ["number"]
}
```

## 多 Agent 适配

三层架构：
1. **Tier 1 原生插件**: Claude Code (.claude-plugin/), OpenCode (.opencode/)
2. **Tier 2 配置适配**: Cursor, Windsurf, Copilot, Gemini CLI, Cline
3. **Tier 3 通用兜底**: AGENTS.md

## 混合审查流程

1. Phase 1: 脚本扫描 → JSON (confirmed + needs_ai_review)
2. Phase 2: AI 深度审查 (needs_ai_review + uncoveredDimensions)
3. Phase 3: 合并结果，计算评分，生成报告
