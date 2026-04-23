# 数据库迁移管理与迭代规则

## 数据库迁移管理

> 数据库 schema 变更必须可追溯、可复现、可回滚，与代码一起走版本控制。

### CHECK-2301 [BLOCKER] schema 变更无版本化管理

- **检测逻辑**: 检查项目中数据库 schema 的管理方式
  - **最佳**: 使用 Flyway / Liquibase 迁移框架，每次变更有版本化 SQL 文件
  - **及格**: 有手动维护的 `docs/db_schema.sql`，且与线上保持一致
  - **不及格**: 无任何 schema 文件，变更靠口头传递或即时消息
- **说明**: 没有版本化管理的 schema 变更，在多人协作和多环境部署时极易出现不一致

```
# 推荐的迁移文件组织（Flyway）
src/main/resources/db/migration/
  V1__init_schema.sql              # 初始建表
  V2__add_status_index.sql         # 加索引
  V3__add_expire_column.sql        # 加字段
  V4__create_order_table.sql       # 新建表
```

### CHECK-2302 [BLOCKER] 迁移文件被修改

- **检测逻辑**: 检查已提交的迁移文件是否被二次修改（Git diff 检测已有 V{n}__ 文件的变更）
- **说明**: Flyway/Liquibase 通过校验和判断文件是否已执行，修改已执行的文件会导致启动报错
- **规则**: 已执行的迁移文件不可修改，只能追加新版本

### CHECK-2303 [MAJOR] 迁移文件缺少回滚方案

- **检测逻辑**: 检查高风险迁移（删列、改类型、删表）是否有对应的回滚 SQL 或回滚说明
- **说明**: 不是所有操作都能回滚（如 DROP COLUMN 数据丢失不可逆），但必须有风险评估

```sql
-- V5__remove_legacy_column.sql
-- 回滚方案: ALTER TABLE user ADD COLUMN legacy_field VARCHAR(100);
-- 风险评估: 该字段已废弃 6 个月，无业务代码引用，数据可丢弃
ALTER TABLE user DROP COLUMN legacy_field;
```

### CHECK-2304 [MAJOR] 迁移文件命名不规范

- **检测逻辑**: 检查迁移文件命名是否遵循框架约定
  - Flyway: `V{版本号}__{描述}.sql`（两个下划线），版本号递增
  - 版本号不能跳跃或重复
- **反例**: `update.sql`、`fix_table.sql`、`V1_init.sql`（单下划线）

### CHECK-2305 [MAJOR] 迁移文件未纳入 Git 版本控制

- **检测逻辑**: 检查迁移目录是否在 `.gitignore` 中（不应被忽略）
- **说明**: 迁移文件必须和业务代码一起走 Git 流程，确保各环境一致

### CHECK-2306 [MINOR] 未配置迁移框架的基线版本

- **检测逻辑**: 对已有线上数据库的项目引入 Flyway，检查是否配置了 `baseline-on-migrate`
- **说明**: 已有数据库首次接入迁移框架时，需设置基线版本跳过已有表结构

```yaml
# 已有数据库首次接入 Flyway 的配置
spring:
  flyway:
    enabled: true
    baseline-on-migrate: true
    baseline-version: 0
```

---

## 数据库迭代规则

> 线上数据库变更必须安全、兼容、可监控，避免锁表和服务中断。

### CHECK-2401 [BLOCKER] DDL 变更未评估锁表风险

- **检测逻辑**: 检查 ALTER TABLE 语句是否涉及以下高风险操作
- **MySQL 锁表风险评估**:

| 操作 | 锁表风险 | 安全建议 |
|------|---------|---------|
| ADD COLUMN（末尾） | 低（MySQL 5.6+ Online DDL） | 可直接执行 |
| ADD COLUMN（非末尾/带默认值） | 中 | 低峰期执行 |
| MODIFY COLUMN（改类型） | 高（全表重建） | 使用 pt-online-schema-change / gh-ost |
| DROP COLUMN | 高（全表重建） | 使用 pt-online-schema-change / gh-ost |
| ADD INDEX | 中（MySQL 5.6+ 支持 Online） | 大表用 `ALGORITHM=INPLACE, LOCK=NONE` |
| DROP TABLE | 低 | 确认无引用后执行 |

```sql
-- ✅ 大表加索引的安全方式
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE, LOCK=NONE;

-- ✅ 超大表用 pt-online-schema-change
pt-online-schema-change --alter "ADD COLUMN remark VARCHAR(500)" D=mydb,t=orders --execute
```

### CHECK-2402 [BLOCKER] 字段变更不向后兼容

- **检测逻辑**: 检查 schema 变更是否与当前运行的代码兼容（滚动发布场景）
- **说明**: K8s 滚动更新时，新旧版本代码会同时运行，schema 变更必须兼容两个版本
- **安全变更流程**:

```
加字段: 先加字段（允许 NULL 或有默认值）→ 部署新代码使用新字段 → 完成
删字段: 先部署新代码不再读写该字段 → 确认无引用 → 再删字段
改字段名: 加新字段 → 双写迁移 → 切换读取到新字段 → 删旧字段（三步完成）
改字段类型: 类似改字段名，避免直接 MODIFY
```

- **反例**: 直接 `ALTER TABLE DROP COLUMN` 一个正在被旧版本代码使用的字段

### CHECK-2403 [BLOCKER] 数据订正未先 SELECT 确认

- **检测逻辑**: UPDATE / DELETE 语句是否带有 WHERE 条件，且执行前先用 SELECT 确认影响范围
- **说明**: 线上数据订正是高危操作，务必先查后改

```sql
-- ✅ 安全的数据订正流程
-- Step 1: 先确认影响范围
SELECT COUNT(*) FROM orders WHERE status = 0 AND created_at < '2025-01-01';
-- 结果: 1523 行

-- Step 2: 备份（可选）
CREATE TABLE orders_backup_20260423 AS
SELECT * FROM orders WHERE status = 0 AND created_at < '2025-01-01';

-- Step 3: 执行订正
UPDATE orders SET status = -1 WHERE status = 0 AND created_at < '2025-01-01';
-- 确认: Rows affected: 1523（与 Step 1 一致）
```

### CHECK-2404 [MAJOR] 新增字段未设置合理默认值

- **检测逻辑**: 检查 ALTER TABLE ADD COLUMN 时字段是否设置了 DEFAULT 值或允许 NULL
- **说明**: 不设默认值且 NOT NULL 会导致：
  - 已有数据行插入失败
  - 旧版本代码写入时缺少该字段报错

```sql
-- ❌ 危险: 已有数据行无法满足 NOT NULL
ALTER TABLE user ADD COLUMN phone VARCHAR(20) NOT NULL;

-- ✅ 安全: 设置默认值
ALTER TABLE user ADD COLUMN phone VARCHAR(20) NOT NULL DEFAULT '';
-- 或允许 NULL
ALTER TABLE user ADD COLUMN phone VARCHAR(20) DEFAULT NULL;
```

### CHECK-2405 [MAJOR] 大表变更未分批执行

- **检测逻辑**: 检查对百万级以上大表的 UPDATE/DELETE 是否做了分批处理
- **说明**: 一次性 UPDATE 百万行会长时间锁表，阻塞其他查询

```sql
-- ❌ 危险: 一次更新百万行
UPDATE orders SET status = -1 WHERE status = 0;

-- ✅ 安全: 分批执行，每批 1000 行
UPDATE orders SET status = -1 WHERE status = 0 LIMIT 1000;
-- 循环执行直到 Rows affected = 0
```

### CHECK-2406 [MAJOR] UPDATE 语句未同步更新 updated_at

- **检测逻辑**: 检查 UPDATE 语句是否包含 `updated_at = NOW()` 或等效设置
- **说明**: 如果表有 `ON UPDATE CURRENT_TIMESTAMP` 则自动更新，否则必须手动设置

### CHECK-2407 [MAJOR] 缺少数据库变更的审批流程

- **检测逻辑**: 检查是否有 DDL 变更的审批机制
- **推荐流程**:

```
开发编写迁移 SQL → 自测通过 → 提交 Code Review → DBA 审核（大表/高危操作）→ 测试环境验证 → 生产执行
```

### CHECK-2408 [MINOR] 废弃表/字段未及时清理

- **检测逻辑**: 检查是否存在代码中已无引用但数据库中仍存在的表或字段
- **说明**: 废弃字段建议先重命名（如加 `_deprecated` 后缀），观察一段时间确认无影响后再删除
