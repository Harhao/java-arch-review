# Java Server Architecture Review Skill

Java 服务端架构审查工具，支持所有主流 AI Agent。通过**可执行脚本确定性扫描 + AI 深度分析**的混合模式，从 19 个核心维度审查 Java/Spring Boot 项目。

## Installation

```bash
npx skills add Harhao/java-arch-review
```

## Quick Start

当用户要求审查 Java 项目时，执行以下流程：

### Step 1: 运行扫描脚本

```bash
bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode full
```

支持的模式：
- `full` — 19 项全量扫描
- `pr` — 仅扫描 git 变更文件
- `focus --dimensions "sql-injection,security"` — 指定维度
- `quick` — 仅 BLOCKER 级别

### Step 2: 解析 JSON 结果

脚本输出 JSON，包含：
- `findings[].type = "confirmed"` — 确定性问题，直接采信
- `findings[].type = "needs_ai_review"` — 可疑点，需要你读代码判断
- `uncoveredDimensions` — 脚本未覆盖的维度，需要你自主审查

### Step 3: AI 深度分析

- 对 `needs_ai_review` 项：读取相关源代码做判断
- 对 `uncoveredDimensions`：读取 `{SKILL_DIR}/references/*.md` 按规则审查
- 综合分析架构合理性

### Step 4: 生成报告

- 合并脚本结果 + AI 分析结果
- 健康度评分：100 - (BLOCKER × 5) - (MAJOR × 2) - (MINOR × 1)
- 按 BLOCKER → MAJOR → MINOR 排序输出

## Supported Agents

| Agent | 状态 | 触发方式 |
|-------|------|---------|
| Claude Code | 原生插件 | `/java-arch-review` 或自然语言 |
| OpenCode | 原生插件 | skill 工具触发 |
| Cursor | Rules 适配 | 自然语言触发 |
| Windsurf | Rules 适配 | 自然语言触发 |
| GitHub Copilot | Instructions 适配 | `@workspace` 触发 |
| Gemini CLI | GEMINI.md 适配 | 自然语言触发 |
| Cline | Rules 适配 | 自然语言触发 |
| Codex CLI | AGENTS.md | 自然语言触发 |

### Agent 配置安装

```bash
# 在目标 Java 项目中执行，自动检测已安装的 Agent
bash {SKILL_DIR}/adapters/setup.sh --project .

# 指定 Agent
bash {SKILL_DIR}/adapters/setup.sh --project . --agent cursor

# 安装所有
bash {SKILL_DIR}/adapters/setup.sh --project . --agent all
```

## Trigger Keywords

以下关键词应触发此 skill：
- 架构审查、设计审查、Java 后端审查、服务端架构
- 后端 CR、工程规范检查、检查工程质量
- server arch review、architecture review、code quality check
- "帮我看看这个 Java 项目"、"review 一下后端代码"

## Full Documentation

- [SKILL.md](./SKILL.md) — 完整的 skill 定义（19 维度、60+ 检查项、报告模板）
- [references/](./references/) — 详细审查规则文件
- [scripts/](./scripts/) — 可执行扫描脚本
- [adapters/](./adapters/) — 多 Agent 适配器
