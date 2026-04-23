# 文档沉淀、测试保障与迭代习惯

## 文档沉淀

> 可运行的项目必须有足够的文档。

### CHECK-1201 [MAJOR] 缺少 README

- **检测逻辑**: 检查项目根目录是否有 `README.md`，包含：
  - 项目简介
  - 环境依赖
  - 本地启动步骤
  - 环境变量说明

### CHECK-1202 [MAJOR] 缺少 API 接口文档

- **检测逻辑**: 检查是否集成了 Swagger/OpenAPI（如 Springdoc）自动生成接口文档
- **检查依赖**: `springdoc-openapi-starter-webmvc-ui` 或 `springfox`

### CHECK-1203 [MINOR] 数据库变更未版本化

- **检测逻辑**: 检查是否有数据库迁移工具（Flyway/Liquibase），或至少有 `docs/db_schema.sql` 手动维护
- **说明**: schema 变更应纳入版本控制，保持文档与线上一致

---

## 测试保障

> 没有测试的代码是不完整的代码。

### CHECK-1301 [BLOCKER] 核心业务逻辑缺少单元测试

- **检测逻辑**: 检查 `src/test/java` 目录中是否存在对应 Service 层的测试类
- **工具**: JUnit 5 + Mockito
- **要求**: Mock 所有外部依赖（数据库、Redis、第三方 API）

### CHECK-1302 [MAJOR] 高风险业务缺少测试覆盖

- **检测逻辑**: 支付、权限、并发等高风险模块必须有单元测试
- **测试命名**: `should_{expectedResult}_when_{scenario}`

```java
@Test
void should_throwNotFoundException_when_orderNotFound() {
    when(orderRepository.findById(9999L)).thenReturn(Optional.empty());
    assertThrows(NotFoundException.class, () -> orderService.getOrder(9999L));
}
```

### CHECK-1303 [MAJOR] CI 流水线缺少测试门禁

- **检测逻辑**: 检查 `.github/workflows/` 或 CI 配置中是否有自动运行测试的步骤
- **说明**: 测试必须全部通过才允许合并到主干

### CHECK-1304 [MINOR] 测试中使用 System.out 而非 assert

- **检测逻辑**: 检查测试方法中是否用 `System.out.println` 输出结果，而非使用断言验证

---

## 良好的迭代习惯

> 代码质量由流程保障，而非仅靠个人自觉。

### CHECK-1401 [MAJOR] 缺少代码格式化/lint 配置

- **检测逻辑**: 检查是否配置了 Checkstyle、SpotBugs 或 pre-commit hook
- **说明**: Git Hook 自动运行 Lint + 格式化，拦截不合规代码提交

### CHECK-1402 [MINOR] Pull Request 流程未强制

- **检测逻辑**: 检查是否有分支保护策略，PR 是否必须经过 Code Review 才能合并
