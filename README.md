# java-server-arch-review

Java 服务端设计架构审查 Skill，基于资深全栈工程师的视角，从 **19 个核心维度**审查 Java/Spring Boot 项目的架构设计合理性与工程实践规范性。

## 安装

```bash
npx skills add Harhao/java-server-arch-review
```

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

### Claude Code

安装后可通过 slash command 触发：

```
/java-arch-review          # 默认 PR 模式
/java-arch-review 全量审查  # Full 模式
/java-arch-review 只看安全  # Focus 安全维度
```

也可以自然语言触发：

```
帮我审查一下这个 Java 项目的架构
review 一下后端代码质量
检查一下工程规范
```

### OpenCode

通过 `skill` 工具触发 `java-server-arch-review` skill。

### 其他 Agent

Skill 会通过 description 自动被识别和触发。

## 项目结构

```
.
├── SKILL.md                    # Skill 主文件（索引路由）
├── references/                 # 详细审查规则
│   ├── _sections.md            # 目录说明
│   ├── coding-standards.md     # 编码规范
│   ├── database-index.md       # 数据库索引
│   ├── sql-injection.md        # SQL 注入防范
│   ├── config-logging.md       # 配置管理 + 日志
│   ├── error-handling.md       # 错误处理
│   ├── code-layering.md        # 代码分层 + DRY
│   ├── security-auth.md        # 认证与权限
│   ├── api-design.md           # RESTful + 参数校验
│   ├── rate-limiting.md        # 限流防护
│   ├── quality-testing.md      # 文档 + 测试 + 迭代
│   ├── data-storage.md         # 存储 + 缓存 + 事务
│   └── db-migration.md         # 迁移 + 迭代规则
├── commands/                   # Claude Code slash commands
│   └── java-arch-review.md
├── .claude-plugin/             # Claude Code plugin manifest
│   └── plugin.json
├── .opencode/                  # OpenCode plugin
│   └── plugins/
│       └── java-arch-review.js
├── AGENTS.md                   # Multi-agent support
├── LICENSE                     # MIT License
└── README.md
```

## License

MIT
