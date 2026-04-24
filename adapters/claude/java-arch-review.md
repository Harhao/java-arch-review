---
description: "对当前 Java/Spring Boot 项目执行架构设计审查，覆盖 19 个核心维度（安全、性能、分层、测试等）。支持 Full/PR/Focus/Quick 四种模式。"
---

请使用 java-arch-review skill 对当前项目执行架构审查。

## 执行流程

### Step 1: 运行扫描脚本

```bash
bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode {MODE}
```

- MODE 默认 full，用户可通过参数指定: full/pr/focus/quick
- 脚本输出 JSON 格式的结构化扫描结果

### Step 2: 解析 JSON 结果

- `findings[].type = "confirmed"` — 确定性问题，直接采信
- `findings[].type = "needs_ai_review"` — 可疑点，需要你读代码判断
- `uncoveredDimensions` — 脚本未覆盖的维度，需要你自主审查

### Step 3: AI 深度分析

- 对 `needs_ai_review` 项：读取相关源代码做判断
- 对 `uncoveredDimensions`：读取 `{SKILL_DIR}/references/*.md` 按规则审查

### Step 4: 生成报告

- 合并脚本结果 + AI 分析结果
- 健康度评分：100 - (BLOCKER x 5) - (MAJOR x 2) - (MINOR x 1)
- 按 BLOCKER -> MAJOR -> MINOR 排序输出

审查模式由用户指定，默认使用 PR 模式。如果用户提供了额外参数（如"全量"、"只看安全"、"quick"），按对应模式执行。

$ARGUMENTS
