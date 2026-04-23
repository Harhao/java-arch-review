# 代码分层与 DRY 原则

## 代码分层与职责单一

> Controller 不写业务逻辑，Service 不写 SQL。

### CHECK-0601 [BLOCKER] Controller 层包含业务逻辑

- **检测逻辑**: 检查 Controller 方法中是否包含：
  - 直接调用 DAO/Mapper 层
  - 复杂条件判断和业务编排
  - 事务管理（`@Transactional`）
- **说明**: Controller 职责仅限：接收请求、参数校验、调用 Service、返回响应

### CHECK-0602 [BLOCKER] Service 层直接操作 HTTP 语义

- **检测逻辑**: Service 层不应出现 `HttpServletRequest`、`HttpServletResponse`、`ResponseEntity` 等 HTTP 相关类
- **说明**: Service 层只处理业务逻辑，不感知传输协议

### CHECK-0603 [MAJOR] 超大 Service 类

- **检测逻辑**: 单个 Service 类超过 500 行或包含超过 20 个公共方法
- **修复建议**: 按业务领域拆分，每个 Service 只负责一个业务领域

### CHECK-0604 [MINOR] 分层领域模型混用

- **检测逻辑**: 检查各层是否使用了正确的领域模型
  - Controller: 接收 VO/Request，返回 VO/Response
  - Service: 使用 BO/DTO
  - DAO: 使用 DO/PO（与数据库表一一对应）
- **反例**: Controller 直接返回 DO 对象给前端

---

## DRY 原则——提取共用逻辑

> Don't Repeat Yourself: 相同逻辑不写两遍。

### CHECK-0701 [MAJOR] 重复代码块

- **检测逻辑**: 检测两处及以上相似度高的代码块（超过 10 行）
- **修复建议**: 提取到 Utils/Helper 类或公共方法

### CHECK-0702 [MAJOR] Magic Number / Magic String

- **检测逻辑**: 检测代码中未定义直接使用的字面量（排除 0、1、-1、""、true、false）
- **修复建议**: 提取为常量或枚举

```java
// ❌ 违规
if (status == 3) { ... }

// ✅ 修复
private static final int STATUS_COMPLETED = 3;
if (status == STATUS_COMPLETED) { ... }
```

### CHECK-0703 [MINOR] 重复校验逻辑未封装

- **检测逻辑**: 多处出现相同的参数校验逻辑，建议封装为独立方法或自定义 Validator
