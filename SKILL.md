---
name: java-arch-review
description: Java 服务端设计架构审查工具，基于资深全栈工程师的视角，审查 Java/Spring Boot 项目的架构设计合理性与工程实践规范性。覆盖数据库索引、SQL 注入防范、配置管理、日志规范、错误处理、代码分层、DRY 原则、认证权限、RESTful 接口设计、参数校验、限流防护、文档沉淀、测试保障、数据存储设计、缓存使用、事务管理、数据库迁移管理、数据库迭代规则等 19 个核心维度。当用户需要审查 Java 服务端代码的架构设计是否合理、工程质量是否达标时使用此 skill。触发关键词：架构审查、设计审查、Java 后端审查、服务端架构、后端 CR、工程规范检查、server arch review、架构合理性。即使用户只是说"帮我看看这个 Java 项目"、"review 一下后端代码"、"检查一下工程质量"也应该触发此 skill。
---

# Java 服务端设计架构审查工具

> 基于资深全栈工程师的视角，从 19 个核心维度审查 Java 服务端架构设计合理性与工程实践规范性。

---

## 一、总体说明

### 1.1 工具定位

本 skill 面向 Java/Spring Boot 服务端项目，提供从编码规范到架构设计的全方位工程审查，独立覆盖服务端开发的 19 个核心维度。

### 1.2 审查维度

共 19 个审查维度，覆盖从编码规范到部署运维的完整链路：

| 序号 | 维度 | 权重 | 参考文件 |
|------|------|------|---------|
| 0 | 需求与编码规范 | 4% | `references/coding-standards.md` |
| 1 | 数据库索引 | 7% | `references/database-index.md` |
| 2 | SQL 注入防范 | 7% | `references/sql-injection.md` |
| 3 | 配置管理 | 5% | `references/config-logging.md` |
| 4 | 可观测性日志 | 5% | `references/config-logging.md` |
| 5 | 错误处理 | 7% | `references/error-handling.md` |
| 6 | 代码分层 | 5% | `references/code-layering.md` |
| 7 | DRY 原则 | 3% | `references/code-layering.md` |
| 8 | 认证与权限 | 7% | `references/security-auth.md` |
| 9 | RESTful 接口 | 5% | `references/api-design.md` |
| 10 | 参数校验与 XSS | 5% | `references/api-design.md` |
| 11 | 限流防护 | 6% | `references/rate-limiting.md` |
| 12 | 文档沉淀 | 3% | `references/quality-testing.md` |
| 13 | 测试保障 | 4% | `references/quality-testing.md` |
| 14 | 数据存储设计 | 6% | `references/data-storage.md` |
| 15 | 缓存使用 | 5% | `references/data-storage.md` |
| 16 | 事务管理 | 5% | `references/data-storage.md` |
| 17 | 数据库迁移管理 | 6% | `references/db-migration.md` |
| 18 | 数据库迭代规则 | 5% | `references/db-migration.md` |

### 1.3 违规等级

| 等级 | 标识 | 含义 |
|------|------|------|
| BLOCKER | `[BLOCKER]` | 必须修复，阻塞合入。涉及安全漏洞、数据损坏风险 |
| MAJOR | `[MAJOR]` | 强烈建议修复。涉及性能问题、维护性问题 |
| MINOR | `[MINOR]` | 建议优化。涉及最佳实践、可读性 |

### 1.4 输出格式

```
[等级] 审查维度编号 | 审查项名称
位置: 文件路径:行号
问题: 具体违规说明
建议: 修复方案及代码示例
```

### 1.5 审查流程

审查采用**脚本扫描 + AI 深度分析**的混合模式，确保结果可复现且全面覆盖。

#### Phase 1：脚本扫描（确定性检测）

执行扫描脚本获取结构化结果：

```bash
bash {SKILL_DIR}/scripts/arch-review.sh --project {PROJECT_PATH} --mode {MODE}
```

参数说明：
- `--project`: 目标 Java 项目路径
- `--mode`: 审查模式 (full/pr/focus/quick)，默认 full
- `--dimensions`: focus 模式下指定维度，如 `"sql-injection,security"`

脚本输出 JSON 格式结果，包含：
- `findings[].type = "confirmed"` — 脚本确定性检测到的问题，直接采信
- `findings[].type = "needs_ai_review"` — 脚本标记的可疑点，需要 AI 深度判断
- `uncoveredDimensions` — 脚本无法覆盖的维度编号，需要 AI 自主审查

#### Phase 2：AI 深度审查

针对脚本无法完全覆盖的部分：

1. **`needs_ai_review` 项**：读取相关源代码，结合 finding 中的 context 信息做判断
2. **`uncoveredDimensions` 维度**：读取对应的 `references/*.md` 规则文件，按规则逐项审查代码
3. **综合分析**：架构合理性、业务逻辑覆盖度等需要理解上下文的审查

#### Phase 3：报告生成

1. 合并 Phase 1 confirmed 结果 + Phase 2 AI 审查结果
2. 计算健康度评分：100 - (BLOCKER × 5) - (MAJOR × 2) - (MINOR × 1)
3. 按模板输出最终 Markdown 报告

### 1.6 脚本覆盖矩阵

| 维度 | 脚本确定性扫描 | AI 深度分析 |
|------|--------------|------------|
| D0 编码规范 | — | CHECK-0001, 0002 |
| D1 数据库索引 | — | CHECK-0101~0105 |
| D2 SQL注入 | CHECK-0201, 0202 | CHECK-0203 |
| D3 配置管理 | CHECK-0301, 0302, 0303 | — |
| D4 日志规范 | CHECK-0401, 0402 | CHECK-0403, 0404 |
| D5 错误处理 | CHECK-0501, 0502 | CHECK-0503, 0504 |
| D6 代码分层 | CHECK-0601, 0602 | CHECK-0603 |
| D7 DRY 原则 | CHECK-0701, 0702 | CHECK-0703 |
| D8 认证权限 | — | CHECK-0801~0803 |
| D9 RESTful 接口 | — | CHECK-0901~0904 |
| D10 参数校验 | CHECK-1001, 1002, 1003 | CHECK-1004 |
| D11 限流防护 | — | CHECK-1101~1108 |
| D12 文档沉淀 | CHECK-1201, 1202 | CHECK-1203 |
| D13 测试保障 | CHECK-1301, 1302, 1303 | CHECK-1304 |
| D14 迭代规范 | — | CHECK-1401, 1402 |
| D15 数据存储 | CHECK-2001~2004 | — |
| D16 缓存使用 | — | CHECK-2101, 2102 |
| D17 事务管理 | — | CHECK-2201, 2202 |
| D18 DB迁移 | CHECK-2301, 2305 | CHECK-2302~2306 |
| D19 DB迭代 | — | CHECK-2401~2408 |

---

## 二、审查清单速查

以下为各维度的检查项索引。每个检查项的详细规则（检测逻辑、示例代码、修复方案）请参阅对应的 `references/` 文件。

### 编码与安全

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-0001 | MAJOR | 命名规范一致性 | `coding-standards.md` |
| CHECK-0002 | MINOR | Commit Message 规范 | `coding-standards.md` |
| CHECK-0101 | BLOCKER | WHERE 条件高频字段缺少索引 | `database-index.md` |
| CHECK-0102 | MAJOR | JOIN 连接字段缺少索引 | `database-index.md` |
| CHECK-0103 | MAJOR | ORDER BY / GROUP BY 字段缺少索引 | `database-index.md` |
| CHECK-0104 | MAJOR | 联合索引未遵循最左前缀原则 | `database-index.md` |
| CHECK-0105 | MINOR | 写多读少场景的过度索引 | `database-index.md` |
| CHECK-0201 | BLOCKER | MyBatis 使用 ${} 替代 #{} | `sql-injection.md` |
| CHECK-0202 | BLOCKER | 字符串拼接 SQL | `sql-injection.md` |
| CHECK-0203 | MAJOR | 数据库账号权限过大 | `sql-injection.md` |

### 工程实践

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-0301 | BLOCKER | 敏感信息硬编码 | `config-logging.md` |
| CHECK-0302 | MAJOR | 未使用多环境配置 | `config-logging.md` |
| CHECK-0303 | MAJOR | 配置值未通过 Spring 注入 | `config-logging.md` |
| CHECK-0401 | BLOCKER | 关键业务操作缺少日志 | `config-logging.md` |
| CHECK-0402 | BLOCKER | 异常捕获后未记录日志 | `config-logging.md` |
| CHECK-0403 | MAJOR | 日志缺少上下文信息 | `config-logging.md` |
| CHECK-0404 | MAJOR | 日志级别使用不当 | `config-logging.md` |
| CHECK-0501 | BLOCKER | 缺少全局异常处理器 | `error-handling.md` |
| CHECK-0502 | BLOCKER | 5xx 错误暴露堆栈信息 | `error-handling.md` |
| CHECK-0503 | MAJOR | 缺少统一业务异常体系 | `error-handling.md` |
| CHECK-0504 | MAJOR | HTTP 状态码使用不当 | `error-handling.md` |

### 代码架构

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-0601 | BLOCKER | Controller 层包含业务逻辑 | `code-layering.md` |
| CHECK-0602 | BLOCKER | Service 层直接操作 HTTP 语义 | `code-layering.md` |
| CHECK-0603 | MAJOR | 超大 Service 类 | `code-layering.md` |
| CHECK-0604 | MINOR | 分层领域模型混用 | `code-layering.md` |
| CHECK-0701 | MAJOR | 重复代码块 | `code-layering.md` |
| CHECK-0702 | MAJOR | Magic Number / Magic String | `code-layering.md` |
| CHECK-0703 | MINOR | 重复校验逻辑未封装 | `code-layering.md` |

### 安全防护

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-0801 | BLOCKER | 接口缺少认证保护 | `security-auth.md` |
| CHECK-0802 | BLOCKER | 资源操作缺少越权检查 | `security-auth.md` |
| CHECK-0803 | MAJOR | Token/Session 方案安全性 | `security-auth.md` |
| CHECK-1001 | BLOCKER | 接口入参未校验 | `api-design.md` |
| CHECK-1002 | BLOCKER | 请求体 VO 缺少校验注解 | `api-design.md` |
| CHECK-1003 | MAJOR | 文件上传未校验类型和大小 | `api-design.md` |
| CHECK-1004 | MAJOR | 输出到前端的内容未转义 | `api-design.md` |
| CHECK-1101 | MAJOR | 公开接口缺少限流 | `rate-limiting.md` |
| CHECK-1102 | BLOCKER | 多实例部署使用本地限流 | `rate-limiting.md` |
| CHECK-1103 | MAJOR | 限流粒度不合理 | `rate-limiting.md` |
| CHECK-1104 | MAJOR | 限流算法选型不当 | `rate-limiting.md` |
| CHECK-1105 | MAJOR | 登录接口缺少暴力破解防护 | `rate-limiting.md` |
| CHECK-1106 | MAJOR | 限流触发后缺少友好响应 | `rate-limiting.md` |
| CHECK-1107 | MINOR | 敏感操作缺少二次验证 | `rate-limiting.md` |
| CHECK-1108 | MINOR | 缺少限流监控和告警 | `rate-limiting.md` |

### API 设计

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-0901 | MAJOR | URL 设计不符合 RESTful | `api-design.md` |
| CHECK-0902 | MAJOR | 响应格式不统一 | `api-design.md` |
| CHECK-0903 | MAJOR | 列表接口缺少分页 | `api-design.md` |
| CHECK-0904 | MINOR | 缺少 API 版本控制 | `api-design.md` |

### 质量保障

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-1201 | MAJOR | 缺少 README | `quality-testing.md` |
| CHECK-1202 | MAJOR | 缺少 API 接口文档 | `quality-testing.md` |
| CHECK-1203 | MINOR | 数据库变更未版本化 | `quality-testing.md` |
| CHECK-1301 | BLOCKER | 核心业务逻辑缺少单元测试 | `quality-testing.md` |
| CHECK-1302 | MAJOR | 高风险业务缺少测试覆盖 | `quality-testing.md` |
| CHECK-1303 | MAJOR | CI 流水线缺少测试门禁 | `quality-testing.md` |
| CHECK-1304 | MINOR | 测试中使用 System.out 而非 assert | `quality-testing.md` |
| CHECK-1401 | MAJOR | 缺少代码格式化/lint 配置 | `quality-testing.md` |
| CHECK-1402 | MINOR | Pull Request 流程未强制 | `quality-testing.md` |

### 数据层架构

| CHECK ID | 等级 | 检查项 | 参考文件 |
|----------|------|--------|---------|
| CHECK-2001 | BLOCKER | 数据查询缺少归属过滤 | `data-storage.md` |
| CHECK-2002 | MAJOR | 表缺少时间戳字段 | `data-storage.md` |
| CHECK-2003 | MAJOR | 未使用软删除 | `data-storage.md` |
| CHECK-2004 | MAJOR | 密码明文存储 | `data-storage.md` |
| CHECK-2101 | MAJOR | 缓存策略不当 | `data-storage.md` |
| CHECK-2102 | MAJOR | 多实例部署未考虑状态共享 | `data-storage.md` |
| CHECK-2201 | BLOCKER | 事务范围不当 | `data-storage.md` |
| CHECK-2202 | BLOCKER | 事务中 catch 异常未回滚 | `data-storage.md` |
| CHECK-2301 | BLOCKER | schema 变更无版本化管理 | `db-migration.md` |
| CHECK-2302 | BLOCKER | 迁移文件被修改 | `db-migration.md` |
| CHECK-2303 | MAJOR | 迁移文件缺少回滚方案 | `db-migration.md` |
| CHECK-2304 | MAJOR | 迁移文件命名不规范 | `db-migration.md` |
| CHECK-2305 | MAJOR | 迁移文件未纳入 Git | `db-migration.md` |
| CHECK-2306 | MINOR | 未配置迁移框架基线版本 | `db-migration.md` |
| CHECK-2401 | BLOCKER | DDL 变更未评估锁表风险 | `db-migration.md` |
| CHECK-2402 | BLOCKER | 字段变更不向后兼容 | `db-migration.md` |
| CHECK-2403 | BLOCKER | 数据订正未先 SELECT 确认 | `db-migration.md` |
| CHECK-2404 | MAJOR | 新增字段未设置合理默认值 | `db-migration.md` |
| CHECK-2405 | MAJOR | 大表变更未分批执行 | `db-migration.md` |
| CHECK-2406 | MAJOR | UPDATE 未同步更新 updated_at | `db-migration.md` |
| CHECK-2407 | MAJOR | 缺少数据库变更审批流程 | `db-migration.md` |
| CHECK-2408 | MINOR | 废弃表/字段未及时清理 | `db-migration.md` |

---

## 三、审查报告模板

审查完成后，按以下模板输出报告：

```markdown
# Java 服务端设计架构审查报告

## 项目信息
- 项目名称: xxx
- 技术栈: Spring Boot x.x / MyBatis-Plus / MySQL / Redis
- 审查范围: [全量扫描 / 增量扫描 / 指定模块]

## 健康度评分: XX/100

## 审查结果统计
| 等级 | 数量 |
|------|------|
| BLOCKER | X |
| MAJOR | X |
| MINOR | X |

## BLOCKER 问题（必须修复）
[按输出格式逐项列出]

## MAJOR 问题（强烈建议修复）
[按输出格式逐项列出]

## MINOR 问题（建议优化）
[按输出格式逐项列出]

## 总结与建议
[1-3 条最关键的改进方向]
```

---

## 四、审查模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **Full** | 19 项维度全量扫描 | 新项目初始化、大版本发布前 |
| **PR** | 仅扫描变更文件涉及的维度 | Pull Request Code Review |
| **Focus** | 指定维度检查 | 专项治理（如安全专项） |
| **Quick** | 仅 BLOCKER 级别 | 快速门禁检查 |

使用方式：
- 默认使用 **PR** 模式
- 用户可通过 "全量审查"、"只看安全" 等表述指定模式
- 执行审查时，根据涉及的维度读取对应的 `references/` 文件获取详细检查规则

**脚本调用示例：**

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

## 五、多 Agent 支持

本 skill 适配主流 AI Agent，每个 Agent 有对应的配置适配器：

| Agent | 适配方式 | 配置文件 |
|-------|---------|---------|
| Claude Code | 原生插件 | `.claude-plugin/plugin.json` + `commands/java-arch-review.md` |
| OpenCode | 原生插件 | `.opencode/plugins/java-arch-review.js` |
| Cursor | Rules 文件 | `adapters/cursor/java-arch-review.mdc` → `.cursor/rules/` |
| Windsurf | Rules 文件 | `adapters/windsurf/windsurfrules.md` → `.windsurfrules` |
| GitHub Copilot | Instructions | `adapters/copilot/copilot-instructions.md` → `.github/copilot-instructions.md` |
| Gemini CLI | GEMINI.md | `adapters/gemini/GEMINI.md` → 项目根目录 |
| Cline | Rules 文件 | `adapters/cline/clinerules.md` → `.clinerules` |

### 一键安装

在目标 Java 项目中执行：

```bash
# 自动检测已安装的 Agent 并配置
bash {SKILL_DIR}/adapters/setup.sh --project .

# 指定 Agent
bash {SKILL_DIR}/adapters/setup.sh --project . --agent cursor

# 安装所有 Agent 配置
bash {SKILL_DIR}/adapters/setup.sh --project . --agent all
```
