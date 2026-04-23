# 需求与编码规范

> 先整理需求文档和编码规范，再开始编码。

## CHECK-0001 [MAJOR] 命名规范一致性

- **检测逻辑**: 检查变量、常量、类名、方法名是否遵循统一命名风格
  - Java: 变量/方法 camelCase，类名 PascalCase，常量 UPPER_SNAKE_CASE
- **检查范围**: 所有 Java 源文件

## CHECK-0002 [MINOR] Commit Message 规范

- **检测逻辑**: 检查 Git 提交记录是否遵循 Conventional Commits 格式
- **正例**: `feat: 添加用户登录接口`、`fix: 修复订单状态异常`
- **反例**: `update`、`fix bug`、`修改了一些东西`
