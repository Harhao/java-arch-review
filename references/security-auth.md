# 身份认证与权限控制

> 每个需要登录的接口必须验证 Token，每个操作必须检查权限。

## CHECK-0801 [BLOCKER] 接口缺少认证保护

- **检测逻辑**: 检查 Controller 接口是否有全局认证拦截器/过滤器，或有认证豁免注解（如 `@Public`、`@Anonymous`）
- **说明**: 未登录用户不应访问需认证接口，应返回 401

## CHECK-0802 [BLOCKER] 资源操作缺少越权检查

- **检测逻辑**: 检查涉及增删改的 Service 方法，操作前是否校验当前用户对该资源的所有权
- **说明**: 用户 A 不能操作用户 B 的数据

```java
// ✅ 越权检查示例
public void deleteOrder(Long orderId, Long currentUserId) {
    Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> new NotFoundException("订单不存在"));
    if (!order.getUserId().equals(currentUserId)) {
        throw new ForbiddenException("无权限操作该订单");
    }
    orderRepository.deleteById(orderId);
}
```

## CHECK-0803 [MAJOR] Token/Session 方案安全性

- **检测逻辑**: 检查认证方案的安全配置
  - JWT: 密钥是否硬编码、过期时间是否合理、是否有 Refresh Token 机制
  - Session: 是否配置 HttpOnly、Secure、SameSite 属性
  - 多实例部署时 Session 是否存储在 Redis 等共享存储
