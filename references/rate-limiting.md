# 接口防御——限流防护

> 对每个公开接口添加限流，防止少数恶意请求压垮服务。

## CHECK-1101 [MAJOR] 公开接口缺少限流

- **检测逻辑**: 检查登录、注册、验证码发送等公开接口是否有限流措施
- **实现方式**: Bucket4j、Spring Cloud Gateway RateLimiter、Nginx limit_req、Redis 计数

## CHECK-1102 [BLOCKER] 多实例部署使用本地限流

- **检测逻辑**: 检查项目是否部署多个实例（K8s Deployment replicas > 1），但限流计数器存在 JVM 内存中
- **说明**: 本地限流在多实例下形同虚设——每个 Pod 各自计数，实际总请求量 = 限制值 x Pod 数
- **修复方案**:

```
方案一（推荐）: Redis 集中计数——所有实例共享同一个计数器
方案二: 网关层限流——Nginx / Spring Cloud Gateway 在入口统一限流
方案三: 均分配额——每个 Pod 分配 总限制/Pod数 的配额（不精确，Pod 扩缩时需调整）
```

```java
// ✅ 基于 Redis + Lua 的分布式限流示例
public boolean isAllowed(String key, int maxRequests, int windowSeconds) {
    String script = """
        local current = redis.call('INCR', KEYS[1])
        if current == 1 then
            redis.call('EXPIRE', KEYS[1], ARGV[1])
        end
        return current
    """;
    Long count = redissonClient.getScript()
        .eval(RScript.Mode.READ_WRITE, script,
              RScript.ReturnType.INTEGER,
              List.of(key), windowSeconds);
    return count <= maxRequests;
}
```

## CHECK-1103 [MAJOR] 限流粒度不合理

- **检测逻辑**: 检查限流的 key 设计是否合理
- **常见粒度**:
  - **IP 限流**: 适合匿名接口，但共享出口 IP（公司/学校）可能误伤正常用户
  - **用户 ID 限流**: 适合已登录接口，精确到人
  - **IP + 接口路径**: 同一 IP 对不同接口分别计数
- **反例**: 全局共用一个计数器，一个用户刷满配额影响所有人

## CHECK-1104 [MAJOR] 限流算法选型不当

- **检测逻辑**: 评估限流算法是否匹配业务场景

| 算法 | 特点 | 适用场景 |
|------|------|---------|
| 固定窗口 | 实现简单，但有窗口边界突发问题 | 精度要求不高的一般接口 |
| 滑动窗口 | 平滑限流，无边界突发 | 需要精确控制速率的接口 |
| 令牌桶 | 允许突发流量，平均速率可控 | 允许短时突发的场景（如秒杀前的预热） |
| 漏桶 | 严格匀速，削峰填谷 | 对下游依赖保护（如第三方 API 调用） |

## CHECK-1105 [MAJOR] 登录接口缺少暴力破解防护

- **检测逻辑**: 检查登录接口是否有错误次数限制（如连续 5 次错误锁定 15 分钟）
- **实现方式**: Redis 记录 `login_fail:{username}` 计数，设置 TTL 自动解锁

## CHECK-1106 [MAJOR] 限流触发后缺少友好响应

- **检测逻辑**: 限流被触发时是否返回了合理的 HTTP 状态码和提示信息
- **要求**:
  - 返回 HTTP 429 Too Many Requests
  - 响应体包含友好提示（如"请求过于频繁，请稍后再试"）
  - 可选：返回 `Retry-After` 头告知客户端多久后可重试

## CHECK-1107 [MINOR] 敏感操作缺少二次验证

- **检测逻辑**: 修改密码、绑定手机、转账等敏感接口是否有额外验证（短信验证码、邮箱验证等）

## CHECK-1108 [MINOR] 缺少限流监控和告警

- **检测逻辑**: 限流触发时是否有日志记录或监控告警
- **说明**: 频繁触发限流可能意味着正在被攻击，或限流阈值设置不合理，需要关注
