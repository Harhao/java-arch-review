# 数据库索引

> 高频查询字段必须加索引。

## CHECK-0101 [BLOCKER] WHERE 条件高频字段缺少索引

- **检测逻辑**: 扫描 MyBatis XML / Mapper 注解中的 SQL，提取 WHERE 条件字段，与表的索引定义对比
- **检查范围**: `*Mapper.java`、`*Mapper.xml`、`QueryWrapper`/`LambdaQueryWrapper` 调用
- **示例**:

```sql
-- 查询频繁使用 user_id 过滤，但表上无索引
SELECT * FROM orders WHERE user_id = #{userId}
-- 建议: CREATE INDEX idx_order_user_id ON orders(user_id);
```

## CHECK-0102 [MAJOR] JOIN 连接字段缺少索引

- **检测逻辑**: 检测 JOIN ON 条件中的字段是否有索引
- **说明**: 无索引的 JOIN 会导致全表扫描，数据量大时性能急剧下降

## CHECK-0103 [MAJOR] ORDER BY / GROUP BY 字段缺少索引

- **检测逻辑**: 排序和分组字段无索引会产生 filesort，检查是否有对应索引

## CHECK-0104 [MAJOR] 联合索引未遵循最左前缀原则

- **检测逻辑**: 检查查询条件是否能命中联合索引的最左前缀
- **示例**:

```sql
-- 索引: (status, created_at)
WHERE created_at > '2025-01-01'          -- 不命中，跳过了 status
WHERE status = 1 AND created_at > '...'  -- 命中
```

## CHECK-0105 [MINOR] 写多读少场景的过度索引

- **检测逻辑**: 评估表的写入频率，高写入场景建索引要慎重
- **说明**: 每个索引都会降低 INSERT/UPDATE/DELETE 速度
