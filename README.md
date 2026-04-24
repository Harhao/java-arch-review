# java-arch-review

Java 服务端设计架构审查工具，通过**可执行脚本确定性扫描 + AI 深度分析**的混合模式，从 **19 个核心维度**审查 Java/Spring Boot 项目的架构设计合理性与工程实践规范性。

支持 **Claude Code、Cursor、Windsurf、GitHub Copilot、Gemini CLI、Cline、OpenCode、Codex CLI** 等主流 AI Agent。

## 安装

```bash
npx skills add Harhao/java-arch-review
```

## 工作原理

```
┌──────────────────────────────────┐
│  Phase 1: 脚本扫描 (确定性)       │
│  bash scripts/arch-review.sh     │
│  输出 JSON 结构化结果              │
├──────────────────────────────────┤
│  Phase 2: AI 深度审查             │
│  对 needs_ai_review 项读代码判断   │
│  对 uncoveredDimensions 自主审查   │
├──────────────────────────────────┤
│  Phase 3: 合并结果，生成报告       │
│  健康度评分 + Markdown 报告       │
└──────────────────────────────────┘
```

脚本覆盖约 60% 的检查项（确定性静态扫描），剩余 40% 由 AI 深度分析完成。

## 覆盖维度

| 类别 | 维度 |
|------|------|
| **编码规范** | 命名规范、Commit Message |
| **数据库** | 索引优化、SQL 注入防范、迁移管理、迭代规则 |
| **安全防护** | 认证权限、参数校验、XSS 防范、限流防护 |
| **工程实践** | 配置管理、日志规范、错误处理 |
| **代码架构** | 分层职责、DRY 原则、RESTful 接口 |
| **质量保障** | 文档沉淀、测试保障、迭代习惯 |
| **数据层** | 存储设计、缓存使用、事务管理 |

## 违规等级

- **BLOCKER** - 必须修复，阻塞合入（安全漏洞、数据损坏风险）
- **MAJOR** - 强烈建议修复（性能问题、维护性问题）
- **MINOR** - 建议优化（最佳实践、可读性）

## 审查模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **Full** | 19 项维度全量扫描 | 新项目初始化、大版本发布前 |
| **PR** | 仅扫描变更文件涉及的维度 | Pull Request Code Review |
| **Focus** | 指定维度检查 | 专项治理（如安全专项） |
| **Quick** | 仅 BLOCKER 级别 | 快速门禁检查 |

## 使用方式

### 脚本直接调用

```bash
# 全量扫描
bash scripts/arch-review.sh --project /path/to/project --mode full

# PR 增量扫描
bash scripts/arch-review.sh --project /path/to/project --mode pr

# 聚焦安全维度
bash scripts/arch-review.sh --project /path/to/project --mode focus --dimensions "sql-injection,secrets,security"

# 快速 BLOCKER 检查
bash scripts/arch-review.sh --project /path/to/project --mode quick
```

### Claude Code

```
/java-arch-review          # 默认 PR 模式
/java-arch-review 全量审查  # Full 模式
/java-arch-review 只看安全  # Focus 安全维度
```

也可以自然语言触发："帮我审查一下这个 Java 项目的架构"

### 其他 Agent

通过 setup 脚本安装对应的 Agent 配置：

```bash
bash adapters/setup.sh --project /path/to/java-project
bash adapters/setup.sh --project /path/to/java-project --agent cursor
bash adapters/setup.sh --project /path/to/java-project --agent all
```

## 支持的 Agent

| Agent | 适配方式 | 触发方式 |
|-------|---------|---------|
| Claude Code | `adapters/claude/` | `/java-arch-review` 或自然语言 |
| OpenCode | `adapters/opencode/` | skill 工具触发 |
| Cursor | `adapters/cursor/` | 自然语言触发 |
| Windsurf | `adapters/windsurf/` | 自然语言触发 |
| GitHub Copilot | `adapters/copilot/` | `@workspace` 触发 |
| Gemini CLI | `adapters/gemini/` | 自然语言触发 |
| Cline | `adapters/cline/` | 自然语言触发 |
| Codex CLI | `AGENTS.md` | 自然语言触发 |

## 项目结构

```
.
├── scripts/                        # 可执行扫描脚本
│   ├── arch-review.sh              # 主入口（AI 调用这一个）
│   └── lib/
│       ├── common.sh               # 公共函数库
│       ├── project-detector.sh     # 项目结构探测
│       ├── check-sql-injection.sh  # SQL 注入检查
│       ├── check-hardcoded-secrets.sh  # 硬编码密钥检查
│       ├── check-config.sh         # 配置管理检查
│       ├── check-logging.sh        # 日志规范检查
│       ├── check-error-handling.sh # 错误处理检查
│       ├── check-code-layering.sh  # 代码分层检查
│       ├── check-dry.sh            # DRY 原则检查
│       ├── check-api-validation.sh # 参数校验检查
│       ├── check-testing.sh        # 测试保障检查
│       ├── check-data-storage.sh   # 数据存储检查
│       └── check-db-migration.sh   # 数据库迁移检查
├── references/                     # 详细审查规则
│   ├── _sections.md
│   ├── coding-standards.md
│   ├── database-index.md
│   ├── sql-injection.md
│   ├── config-logging.md
│   ├── error-handling.md
│   ├── code-layering.md
│   ├── security-auth.md
│   ├── api-design.md
│   ├── rate-limiting.md
│   ├── quality-testing.md
│   ├── data-storage.md
│   └── db-migration.md
├── adapters/                       # 多 Agent 适配器（统一管理）
│   ├── setup.sh                    # 一键安装脚本
│   ├── claude/                     # Claude Code (plugin.json + slash command)
│   ├── opencode/                   # OpenCode (plugin JS)
│   ├── cursor/                     # Cursor (.mdc rules)
│   ├── windsurf/                   # Windsurf (.windsurfrules)
│   ├── copilot/                    # GitHub Copilot (instructions)
│   ├── gemini/                     # Gemini CLI (GEMINI.md)
│   └── cline/                      # Cline (.clinerules)
├── .claude-plugin/                 # Claude Code 插件（根目录，插件系统要求）
│   └── plugin.json
├── .opencode/                      # OpenCode 插件（根目录，插件系统要求）
│   └── plugins/
│       └── java-arch-review.js
├── commands/                       # Claude Code slash commands（根目录）
│   └── java-arch-review.md
├── SKILL.md                        # Skill 主定义文件
├── AGENTS.md                       # 通用 Agent 指令
├── LICENSE                         # MIT License
└── README.md
```

## License

MIT
