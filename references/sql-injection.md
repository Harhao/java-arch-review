# SQL 注入防范

> 使用 ORM；无法使用 ORM 时必须参数化查询。

## CHECK-0201 [BLOCKER] MyBatis 使用 ${} 替代 #{}

- **检测逻辑**: 扫描所有 MyBatis XML 和注解，检测 `${}` 参数绑定
- **说明**: `${}` 是字符串直接替换，存在 SQL 注入风险；`#{}` 使用 PreparedStatement 参数化

```java
// ❌ 危险
@Select("SELECT * FROM user WHERE name = '${name}'")

// ✅ 安全
@Select("SELECT * FROM user WHERE name = #{name}")
```

## CHECK-0202 [BLOCKER] 字符串拼接 SQL

- **检测逻辑**: 检测代码中通过字符串拼接构造 SQL 语句
- **检查范围**: `String sql = "SELECT...` + 变量拼接模式

```java
// ❌ 危险
String sql = "SELECT * FROM user WHERE name = '" + name + "'";

// ✅ 安全: 使用 PreparedStatement
PreparedStatement stmt = conn.prepareStatement("SELECT * FROM user WHERE name = ?");
stmt.setString(1, name);
```

## CHECK-0203 [MAJOR] 数据库账号权限过大

- **检测逻辑**: 检查数据源配置中的数据库用户名，不应使用 root 账号
- **说明**: 遵循最小权限原则
