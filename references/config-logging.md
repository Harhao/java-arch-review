# 配置管理与可观测性日志

## 配置管理——避免 Hard Code

> 所有可变配置、敏感信息一律进配置文件或环境变量，不得硬编码进代码。

### CHECK-0301 [BLOCKER] 敏感信息硬编码

- **检测逻辑**: 扫描代码中的疑似密码、密钥、Token 等硬编码字符串
- **检查范围**: `password`、`secret`、`apiKey`、`token`、`credential` 等关键词附近的字符串赋值
- **检查文件**: `.java`、`.properties`、`.yml`（排除 `application-local.yml`）

```yaml
# ❌ 违规
jwt:
  secret: "my-super-secret-key-12345"

# ✅ 安全
jwt:
  secret: ${JWT_SECRET}
```

### CHECK-0302 [MAJOR] 未使用多环境配置

- **检测逻辑**: 检查是否存在多环境配置文件（`application-dev.yml`、`application-test.yml`、`application-release.yml`）
- **说明**: 生产/测试/开发使用不同配置，绝不将生产凭证提交到代码仓库

### CHECK-0303 [MAJOR] 配置值未通过 @Value 或 @ConfigurationProperties 读取

- **检测逻辑**: 检测业务代码中直接读取 System.getenv() 或 System.getProperty()，而非通过 Spring 的配置注入

---

## 可观测性——高信息量日志

> 每个关键操作都应有日志输出，日志必须包含足够的上下文信息。

### CHECK-0401 [BLOCKER] 关键业务操作缺少日志

- **检测逻辑**: 检查 Service 层的核心业务方法（如创建、更新、删除、支付等）是否有 INFO 级别日志
- **检查范围**: `*Service.java`、`*ServiceImpl.java`

### CHECK-0402 [BLOCKER] 异常捕获后未记录日志

- **检测逻辑**: 检测 catch 块中缺少 `log.error`/`log.warn` 的情况
- **说明**: 不能吞掉异常不记录

```java
// ❌ 违规
catch (Exception e) {
    throw new BizException("操作失败");
}

// ✅ 修复
catch (Exception e) {
    log.error("[Order] 创建订单失败, userId={}, error={}", userId, e.getMessage(), e);
    throw new BizException("操作失败");
}
```

### CHECK-0403 [MAJOR] 日志缺少上下文信息

- **检测逻辑**: 检测低信息量日志，如 `log.info("操作成功")`，缺少 userId、requestId、操作对象等关键字段
- **正例**: `log.info("[Order] 创建订单成功, userId={}, orderId={}, amount={}", userId, orderId, amount)`

### CHECK-0404 [MAJOR] 日志级别使用不当

- **检测逻辑**:
  - DEBUG: 开发调试信息
  - INFO: 业务流程关键节点
  - WARN: 预期内异常（如用户输入参数错误）
  - ERROR: 需处置的错误（系统异常、第三方调用失败等）
- **常见问题**: 用户参数校验失败用了 ERROR，应用 WARN
