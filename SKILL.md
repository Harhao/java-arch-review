---
name: java-server-arch-review
description: Java 服务端设计架构审查工具，基于资深全栈工程师的视角，审查 Java/Spring Boot 项目的架构设计合理性与工程实践规范性。覆盖数据库索引、SQL 注入防范、配置管理、日志规范、错误处理、代码分层、DRY 原则、认证权限、RESTful 接口设计、参数校验、限流防护、文档沉淀、测试保障、数据存储设计、缓存使用、事务管理、数据库迁移管理、数据库迭代规则等 19 个核心维度。当用户需要审查 Java 服务端代码的架构设计是否合理、工程质量是否达标时使用此 skill。触发关键词：架构审查、设计审查、Java 后端审查、服务端架构、后端 CR、工程规范检查、server arch review、架构合理性。
---

# Java 服务端设计架构审查工具

> 基于资深全栈工程师的视角，从 19 个核心维度审查 Java 服务端架构设计合理性与工程实践规范性。

---

## 一、总体说明

### 1.1 工具定位

本 skill 面向 Java/Spring Boot 服务端项目，提供从编码规范到架构设计的全方位工程审查，独立覆盖服务端开发的 19 个核心维度。

### 1.2 审查维度

共 19 个审查维度，覆盖从编码规范到部署运维的完整链路：

| 序号 | 维度 | 权重 | 对应章节 |
|------|------|------|---------|
| 0 | 需求与编码规范 | 4% | §2.0 |
| 1 | 数据库索引 | 7% | §2.1 |
| 2 | SQL 注入防范 | 7% | §2.2 |
| 3 | 配置管理 | 5% | §2.3 |
| 4 | 可观测性日志 | 5% | §2.4 |
| 5 | 错误处理 | 7% | §2.5 |
| 6 | 代码分层 | 5% | §2.6 |
| 7 | DRY 原则 | 3% | §2.7 |
| 8 | 认证与权限 | 7% | §2.8 |
| 9 | RESTful 接口 | 5% | §2.9 |
| 10 | 参数校验与 XSS | 5% | §2.10 |
| 11 | 限流防护 | 6% | §2.11 |
| 12 | 文档沉淀 | 3% | §2.12 |
| 13 | 测试保障 | 4% | §2.13 |
| 14 | 数据存储设计 | 6% | §3.1 |
| 15 | 缓存使用 | 5% | §3.2 |
| 16 | 事务管理 | 5% | §3.3 |
| 17 | 数据库迁移管理 | 6% | §3.4 |
| 18 | 数据库迭代规则 | 5% | §3.5 |

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

1. **识别项目结构**：确认技术栈（Spring Boot 版本、ORM 框架、数据库类型）
2. **按维度逐项扫描**：依次检查 19 个维度
3. **输出审查报告**：按严重等级排序，先 BLOCKER，再 MAJOR，最后 MINOR
4. **给出健康度评分**：0-100 分，BLOCKER 每项扣 5 分，MAJOR 扣 2 分，MINOR 扣 1 分

---

## 二、审查清单

### 2.0 需求与编码规范

> 先整理需求文档和编码规范，再开始编码。

#### CHECK-0001 [MAJOR] 命名规范一致性

- **检测逻辑**: 检查变量、常量、类名、方法名是否遵循统一命名风格
  - Java: 变量/方法 camelCase，类名 PascalCase，常量 UPPER_SNAKE_CASE
- **检查范围**: 所有 Java 源文件

#### CHECK-0002 [MINOR] Commit Message 规范

- **检测逻辑**: 检查 Git 提交记录是否遵循 Conventional Commits 格式
- **正例**: `feat: 添加用户登录接口`、`fix: 修复订单状态异常`
- **反例**: `update`、`fix bug`、`修改了一些东西`

---

### 2.1 数据库索引

> 高频查询字段必须加索引。

#### CHECK-0101 [BLOCKER] WHERE 条件高频字段缺少索引

- **检测逻辑**: 扫描 MyBatis XML / Mapper 注解中的 SQL，提取 WHERE 条件字段，与表的索引定义对比
- **检查范围**: `*Mapper.java`、`*Mapper.xml`、`QueryWrapper`/`LambdaQueryWrapper` 调用
- **示例**:

```sql
-- 查询频繁使用 user_id 过滤，但表上无索引
SELECT * FROM orders WHERE user_id = #{userId}
-- 建议: CREATE INDEX idx_order_user_id ON orders(user_id);
```

#### CHECK-0102 [MAJOR] JOIN 连接字段缺少索引

- **检测逻辑**: 检测 JOIN ON 条件中的字段是否有索引
- **说明**: 无索引的 JOIN 会导致全表扫描，数据量大时性能急剧下降

#### CHECK-0103 [MAJOR] ORDER BY / GROUP BY 字段缺少索引

- **检测逻辑**: 排序和分组字段无索引会产生 filesort，检查是否有对应索引

#### CHECK-0104 [MAJOR] 联合索引未遵循最左前缀原则

- **检测逻辑**: 检查查询条件是否能命中联合索引的最左前缀
- **示例**:

```sql
-- 索引: (status, created_at)
WHERE created_at > '2025-01-01'          -- 不命中，跳过了 status
WHERE status = 1 AND created_at > '...'  -- 命中
```

#### CHECK-0105 [MINOR] 写多读少场景的过度索引

- **检测逻辑**: 评估表的写入频率，高写入场景建索引要慎重
- **说明**: 每个索引都会降低 INSERT/UPDATE/DELETE 速度

---

### 2.2 SQL 注入防范

> 使用 ORM；无法使用 ORM 时必须参数化查询。

#### CHECK-0201 [BLOCKER] MyBatis 使用 ${} 替代 #{}

- **检测逻辑**: 扫描所有 MyBatis XML 和注解，检测 `${}` 参数绑定
- **说明**: `${}` 是字符串直接替换，存在 SQL 注入风险；`#{}` 使用 PreparedStatement 参数化

```java
// ❌ 危险
@Select("SELECT * FROM user WHERE name = '${name}'")

// ✅ 安全
@Select("SELECT * FROM user WHERE name = #{name}")
```

#### CHECK-0202 [BLOCKER] 字符串拼接 SQL

- **检测逻辑**: 检测代码中通过字符串拼接构造 SQL 语句
- **检查范围**: `String sql = "SELECT...` + 变量拼接模式

```java
// ❌ 危险
String sql = "SELECT * FROM user WHERE name = '" + name + "'";

// ✅ 安全: 使用 PreparedStatement
PreparedStatement stmt = conn.prepareStatement("SELECT * FROM user WHERE name = ?");
stmt.setString(1, name);
```

#### CHECK-0203 [MAJOR] 数据库账号权限过大

- **检测逻辑**: 检查数据源配置中的数据库用户名，不应使用 root 账号
- **说明**: 遵循最小权限原则

---

### 2.3 配置管理——避免 Hard Code

> 所有可变配置、敏感信息一律进配置文件或环境变量，不得硬编码进代码。

#### CHECK-0301 [BLOCKER] 敏感信息硬编码

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

#### CHECK-0302 [MAJOR] 未使用多环境配置

- **检测逻辑**: 检查是否存在多环境配置文件（`application-dev.yml`、`application-test.yml`、`application-release.yml`）
- **说明**: 生产/测试/开发使用不同配置，绝不将生产凭证提交到代码仓库

#### CHECK-0303 [MAJOR] 配置值未通过 @Value 或 @ConfigurationProperties 读取

- **检测逻辑**: 检测业务代码中直接读取 System.getenv() 或 System.getProperty()，而非通过 Spring 的配置注入

---

### 2.4 可观测性——高信息量日志

> 每个关键操作都应有日志输出，日志必须包含足够的上下文信息。

#### CHECK-0401 [BLOCKER] 关键业务操作缺少日志

- **检测逻辑**: 检查 Service 层的核心业务方法（如创建、更新、删除、支付等）是否有 INFO 级别日志
- **检查范围**: `*Service.java`、`*ServiceImpl.java`

#### CHECK-0402 [BLOCKER] 异常捕获后未记录日志

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

#### CHECK-0403 [MAJOR] 日志缺少上下文信息

- **检测逻辑**: 检测低信息量日志，如 `log.info("操作成功")`，缺少 userId、requestId、操作对象等关键字段
- **正例**: `log.info("[Order] 创建订单成功, userId={}, orderId={}, amount={}", userId, orderId, amount)`

#### CHECK-0404 [MAJOR] 日志级别使用不当

- **检测逻辑**:
  - DEBUG: 开发调试信息
  - INFO: 业务流程关键节点
  - WARN: 预期内异常（如用户输入参数错误）
  - ERROR: 需处置的错误（系统异常、第三方调用失败等）
- **常见问题**: 用户参数校验失败用了 ERROR，应用 WARN

---

### 2.5 错误处理完备

> 不将设计方案之外的异常展示给用户。

#### CHECK-0501 [BLOCKER] 缺少全局异常处理器

- **检测逻辑**: 检查项目中是否存在 `@RestControllerAdvice` + `@ExceptionHandler` 的全局异常处理器
- **必须处理**: `BizException`（业务异常）、`MethodArgumentNotValidException`（参数校验）、`Exception`（兜底）

```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(BizException.class)
    public ResponseEntity<Response<?>> handleBiz(BizException ex) {
        log.warn("[BizException] code={}, msg={}", ex.getCode(), ex.getMessage());
        return ResponseEntity.status(ex.getHttpStatus())
            .body(Response.error(ex.getCode(), ex.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Response<?>> handleUnknown(Exception ex) {
        log.error("[未预期异常]", ex);
        return ResponseEntity.status(500)
            .body(Response.error("INTERNAL_ERROR", "服务系统异常，请稍后再试"));
    }
}
```

#### CHECK-0502 [BLOCKER] 5xx 错误暴露堆栈信息给前端

- **检测逻辑**: 检查全局异常处理器中，未预期异常是否返回了 `e.getMessage()` 或完整堆栈
- **说明**: 堆栈信息包含内部实现细节，暴露给前端是安全风险

#### CHECK-0503 [MAJOR] 缺少统一的业务异常体系

- **检测逻辑**: 检查是否定义了 BizException 基类及常见子类（NotFoundException、ForbiddenException 等）
- **说明**: 每种错误情况应有明确的错误码和 HTTP 状态码

#### CHECK-0504 [MAJOR] HTTP 状态码使用不当

- **检测逻辑**: 检查 Controller 返回的 HTTP 状态码是否与语义匹配
  - 404: 资源不存在
  - 403: 无权限
  - 409: 资源冲突
  - 不应所有错误都返回 200 + 错误码

---

### 2.6 代码分层与职责单一

> Controller 不写业务逻辑，Service 不写 SQL。

#### CHECK-0601 [BLOCKER] Controller 层包含业务逻辑

- **检测逻辑**: 检查 Controller 方法中是否包含：
  - 直接调用 DAO/Mapper 层
  - 复杂条件判断和业务编排
  - 事务管理（`@Transactional`）
- **说明**: Controller 职责仅限：接收请求、参数校验、调用 Service、返回响应

#### CHECK-0602 [BLOCKER] Service 层直接操作 HTTP 语义

- **检测逻辑**: Service 层不应出现 `HttpServletRequest`、`HttpServletResponse`、`ResponseEntity` 等 HTTP 相关类
- **说明**: Service 层只处理业务逻辑，不感知传输协议

#### CHECK-0603 [MAJOR] 超大 Service 类

- **检测逻辑**: 单个 Service 类超过 500 行或包含超过 20 个公共方法
- **修复建议**: 按业务领域拆分，每个 Service 只负责一个业务领域

#### CHECK-0604 [MINOR] 分层领域模型混用

- **检测逻辑**: 检查各层是否使用了正确的领域模型
  - Controller: 接收 VO/Request，返回 VO/Response
  - Service: 使用 BO/DTO
  - DAO: 使用 DO/PO（与数据库表一一对应）
- **反例**: Controller 直接返回 DO 对象给前端

---

### 2.7 DRY 原则——提取共用逻辑

> Don't Repeat Yourself: 相同逻辑不写两遍。

#### CHECK-0701 [MAJOR] 重复代码块

- **检测逻辑**: 检测两处及以上相似度高的代码块（超过 10 行）
- **修复建议**: 提取到 Utils/Helper 类或公共方法

#### CHECK-0702 [MAJOR] Magic Number / Magic String

- **检测逻辑**: 检测代码中未定义直接使用的字面量（排除 0、1、-1、""、true、false）
- **修复建议**: 提取为常量或枚举

```java
// ❌ 违规
if (status == 3) { ... }

// ✅ 修复
private static final int STATUS_COMPLETED = 3;
if (status == STATUS_COMPLETED) { ... }
```

#### CHECK-0703 [MINOR] 重复校验逻辑未封装

- **检测逻辑**: 多处出现相同的参数校验逻辑，建议封装为独立方法或自定义 Validator

---

### 2.8 身份认证与权限控制

> 每个需要登录的接口必须验证 Token，每个操作必须检查权限。

#### CHECK-0801 [BLOCKER] 接口缺少认证保护

- **检测逻辑**: 检查 Controller 接口是否有全局认证拦截器/过滤器，或有认证豁免注解（如 `@Public`、`@Anonymous`）
- **说明**: 未登录用户不应访问需认证接口，应返回 401

#### CHECK-0802 [BLOCKER] 资源操作缺少越权检查

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

#### CHECK-0803 [MAJOR] Token/Session 方案安全性

- **检测逻辑**: 检查认证方案的安全配置
  - JWT: 密钥是否硬编码、过期时间是否合理、是否有 Refresh Token 机制
  - Session: 是否配置 HttpOnly、Secure、SameSite 属性
  - 多实例部署时 Session 是否存储在 Redis 等共享存储

---

### 2.9 RESTful 接口设计

> 用 URL 表示资源，用 HTTP Method 表示操作，返回正确的状态码。

#### CHECK-0901 [MAJOR] URL 设计不符合 RESTful

- **检测逻辑**: 检查 Controller 的 `@RequestMapping` 路径
- **正例**:

```
GET    /api/v1/orders          → 获取列表   200
GET    /api/v1/orders/{id}     → 获取详情   200 / 404
POST   /api/v1/orders          → 创建       201
PUT    /api/v1/orders/{id}     → 更新       200 / 404
DELETE /api/v1/orders/{id}     → 删除       204 / 404
```

- **反例**: `GET /api/getOrders`、`POST /api/createOrder`、`POST /api/deleteOrder`

#### CHECK-0902 [MAJOR] 响应格式不统一

- **检测逻辑**: 检查所有 Controller 方法的返回类型是否使用统一的响应信封
- **标准格式**:

```json
{ "code": "OK",    "data": { ... } }
{ "code": "NOT_FOUND", "message": "...", "data": null }
```

#### CHECK-0903 [MAJOR] 列表接口缺少分页

- **检测逻辑**: 检查返回列表数据的接口是否支持分页参数
- **说明**: 无分页的列表接口在数据量增长后会导致性能问题和前端渲染卡顿
- **两种策略**: Offset（`?page=1&size=20`）适合后台管理；Cursor（`?cursor=xxx&size=20`）适合无限滚动

#### CHECK-0904 [MINOR] 缺少 API 版本控制

- **检测逻辑**: 检查接口路径中是否包含版本号（如 `/api/v1/`）

---

### 2.10 参数校验与 XSS 防范

> 所有接口入参必须校验，永远不信任用户输入。

#### CHECK-1001 [BLOCKER] 接口入参未校验

- **检测逻辑**: 检查 Controller 的 `@RequestBody` 参数是否使用 `@Valid`/`@Validated`
- **检查范围**: POST/PUT 请求的请求体

```java
// ❌ 违规
@PostMapping("/orders")
public Response<?> createOrder(@RequestBody CreateOrderRequest req) { ... }

// ✅ 修复
@PostMapping("/orders")
public Response<?> createOrder(@RequestBody @Valid CreateOrderRequest req) { ... }
```

#### CHECK-1002 [BLOCKER] 请求体 VO 缺少校验注解

- **检测逻辑**: 检查请求 VO/DTO 类的字段是否有 Jakarta Bean Validation 注解
- **常用注解**: `@NotNull`、`@NotBlank`、`@Size`、`@Min`、`@Max`、`@Pattern`、`@Email`

```java
public record CreateOrderRequest(
    @NotNull Long productId,
    @Min(1) @Max(999) Integer quantity,
    @NotBlank @Size(max = 200) String remark
) {}
```

#### CHECK-1003 [MAJOR] 文件上传未校验类型和大小

- **检测逻辑**: 检查文件上传接口是否校验了文件类型（MIME type）和文件大小
- **说明**: 防止恶意文件上传

#### CHECK-1004 [MAJOR] 输出到前端的内容未转义

- **检测逻辑**: 检查向 HTML 输出的用户生成内容是否做了 XSS 转义

---

### 2.11 接口防御——限流防护

> 对每个公开接口添加限流，防止少数恶意请求压垮服务。

#### CHECK-1101 [MAJOR] 公开接口缺少限流

- **检测逻辑**: 检查登录、注册、验证码发送等公开接口是否有限流措施
- **实现方式**: Bucket4j、Spring Cloud Gateway RateLimiter、Nginx limit_req、Redis 计数

#### CHECK-1102 [BLOCKER] 多实例部署使用本地限流

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

#### CHECK-1103 [MAJOR] 限流粒度不合理

- **检测逻辑**: 检查限流的 key 设计是否合理
- **常见粒度**:
  - **IP 限流**: 适合匿名接口，但共享出口 IP（公司/学校）可能误伤正常用户
  - **用户 ID 限流**: 适合已登录接口，精确到人
  - **IP + 接口路径**: 同一 IP 对不同接口分别计数
- **反例**: 全局共用一个计数器，一个用户刷满配额影响所有人

#### CHECK-1104 [MAJOR] 限流算法选型不当

- **检测逻辑**: 评估限流算法是否匹配业务场景

| 算法 | 特点 | 适用场景 |
|------|------|---------|
| 固定窗口 | 实现简单，但有窗口边界突发问题 | 精度要求不高的一般接口 |
| 滑动窗口 | 平滑限流，无边界突发 | 需要精确控制速率的接口 |
| 令牌桶 | 允许突发流量，平均速率可控 | 允许短时突发的场景（如秒杀前的预热） |
| 漏桶 | 严格匀速，削峰填谷 | 对下游依赖保护（如第三方 API 调用） |

#### CHECK-1105 [MAJOR] 登录接口缺少暴力破解防护

- **检测逻辑**: 检查登录接口是否有错误次数限制（如连续 5 次错误锁定 15 分钟）
- **实现方式**: Redis 记录 `login_fail:{username}` 计数，设置 TTL 自动解锁

#### CHECK-1106 [MAJOR] 限流触发后缺少友好响应

- **检测逻辑**: 限流被触发时是否返回了合理的 HTTP 状态码和提示信息
- **要求**:
  - 返回 HTTP 429 Too Many Requests
  - 响应体包含友好提示（如"请求过于频繁，请稍后再试"）
  - 可选：返回 `Retry-After` 头告知客户端多久后可重试

#### CHECK-1107 [MINOR] 敏感操作缺少二次验证

- **检测逻辑**: 修改密码、绑定手机、转账等敏感接口是否有额外验证（短信验证码、邮箱验证等）

#### CHECK-1108 [MINOR] 缺少限流监控和告警

- **检测逻辑**: 限流触发时是否有日志记录或监控告警
- **说明**: 频繁触发限流可能意味着正在被攻击，或限流阈值设置不合理，需要关注

---

### 2.12 文档沉淀

> 可运行的项目必须有足够的文档。

#### CHECK-1201 [MAJOR] 缺少 README

- **检测逻辑**: 检查项目根目录是否有 `README.md`，包含：
  - 项目简介
  - 环境依赖
  - 本地启动步骤
  - 环境变量说明

#### CHECK-1202 [MAJOR] 缺少 API 接口文档

- **检测逻辑**: 检查是否集成了 Swagger/OpenAPI（如 Springdoc）自动生成接口文档
- **检查依赖**: `springdoc-openapi-starter-webmvc-ui` 或 `springfox`

#### CHECK-1203 [MINOR] 数据库变更未版本化

- **检测逻辑**: 检查是否有数据库迁移工具（Flyway/Liquibase），或至少有 `docs/db_schema.sql` 手动维护
- **说明**: schema 变更应纳入版本控制，保持文档与线上一致

---

### 2.13 测试保障

> 没有测试的代码是不完整的代码。

#### CHECK-1301 [BLOCKER] 核心业务逻辑缺少单元测试

- **检测逻辑**: 检查 `src/test/java` 目录中是否存在对应 Service 层的测试类
- **工具**: JUnit 5 + Mockito
- **要求**: Mock 所有外部依赖（数据库、Redis、第三方 API）

#### CHECK-1302 [MAJOR] 高风险业务缺少测试覆盖

- **检测逻辑**: 支付、权限、并发等高风险模块必须有单元测试
- **测试命名**: `should_{expectedResult}_when_{scenario}`

```java
@Test
void should_throwNotFoundException_when_orderNotFound() {
    when(orderRepository.findById(9999L)).thenReturn(Optional.empty());
    assertThrows(NotFoundException.class, () -> orderService.getOrder(9999L));
}
```

#### CHECK-1303 [MAJOR] CI 流水线缺少测试门禁

- **检测逻辑**: 检查 `.github/workflows/` 或 CI 配置中是否有自动运行测试的步骤
- **说明**: 测试必须全部通过才允许合并到主干

#### CHECK-1304 [MINOR] 测试中使用 System.out 而非 assert

- **检测逻辑**: 检查测试方法中是否用 `System.out.println` 输出结果，而非使用断言验证

---

### 2.14 良好的迭代习惯

> 代码质量由流程保障，而非仅靠个人自觉。

#### CHECK-1401 [MAJOR] 缺少代码格式化/lint 配置

- **检测逻辑**: 检查是否配置了 Checkstyle、SpotBugs 或 pre-commit hook
- **说明**: Git Hook 自动运行 Lint + 格式化，拦截不合规代码提交

#### CHECK-1402 [MINOR] Pull Request 流程未强制

- **检测逻辑**: 检查是否有分支保护策略，PR 是否必须经过 Code Review 才能合并

---

## 三、架构层面审查

以下审查项属于架构设计和数据库运维层面的审查，对应维度 14-18。

### 3.1 数据存储设计

#### CHECK-2001 [BLOCKER] 数据查询缺少归属过滤

- **检测逻辑**: 检查查询语句是否包含 `user_id` 等归属字段的过滤条件
- **说明**: 后端数据是全用户共享的，每个查询都要确保用户只能查到自己的数据

#### CHECK-2002 [MAJOR] 表缺少 created_at / updated_at 时间戳字段

- **检测逻辑**: 检查建表语句或实体类中是否包含创建时间和更新时间字段
- **说明**: 每张表都应有 `created_at` 和 `updated_at`，这是行业惯例

#### CHECK-2003 [MAJOR] 未使用软删除

- **检测逻辑**: 检查 DELETE 操作是否为硬删除（`DELETE FROM`），建议改为软删除（`UPDATE SET deleted = 1`）
- **说明**: 线上系统几乎都用软删除，便于数据恢复、审计追溯

#### CHECK-2004 [MAJOR] 密码明文存储

- **检测逻辑**: 检查 password 相关字段是否经过哈希处理（BCrypt/SCrypt/Argon2）
- **说明**: 永远不存明文密码

### 3.2 缓存使用

#### CHECK-2101 [MAJOR] 缓存策略不当

- **检测逻辑**: 检查 Redis 缓存使用是否设置了 TTL（过期时间）
- **说明**: 无 TTL 的缓存可能导致数据不一致和内存持续增长

#### CHECK-2102 [MAJOR] 多实例部署未考虑状态共享

- **检测逻辑**: 检查是否有将 Session、缓存等状态存在 JVM 内存（如 `static Map`）的情况
- **说明**: 多实例部署时，JVM 内存中的状态无法跨实例共享，应使用 Redis 等共享存储

### 3.3 事务管理

#### CHECK-2201 [BLOCKER] 事务范围不当

- **检测逻辑**: 检查 `@Transactional` 的使用
  - 事务范围过大：包含了非数据库操作（如 HTTP 调用、消息发送）
  - 事务范围过小：一组必须原子性的操作未包在同一事务中

#### CHECK-2202 [BLOCKER] 事务中 catch 异常未回滚

- **检测逻辑**: `@Transactional` 方法中 try-catch 后既没有重新抛出异常，也没有手动设置回滚

---

### 3.4 数据库迁移管理

> 数据库 schema 变更必须可追溯、可复现、可回滚，与代码一起走版本控制。

#### CHECK-2301 [BLOCKER] schema 变更无版本化管理

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

#### CHECK-2302 [BLOCKER] 迁移文件被修改

- **检测逻辑**: 检查已提交的迁移文件是否被二次修改（Git diff 检测已有 V{n}__ 文件的变更）
- **说明**: Flyway/Liquibase 通过校验和判断文件是否已执行，修改已执行的文件会导致启动报错
- **规则**: 已执行的迁移文件不可修改，只能追加新版本

#### CHECK-2303 [MAJOR] 迁移文件缺少回滚方案

- **检测逻辑**: 检查高风险迁移（删列、改类型、删表）是否有对应的回滚 SQL 或回滚说明
- **说明**: 不是所有操作都能回滚（如 DROP COLUMN 数据丢失不可逆），但必须有风险评估

```sql
-- V5__remove_legacy_column.sql
-- 回滚方案: ALTER TABLE user ADD COLUMN legacy_field VARCHAR(100);
-- 风险评估: 该字段已废弃 6 个月，无业务代码引用，数据可丢弃
ALTER TABLE user DROP COLUMN legacy_field;
```

#### CHECK-2304 [MAJOR] 迁移文件命名不规范

- **检测逻辑**: 检查迁移文件命名是否遵循框架约定
  - Flyway: `V{版本号}__{描述}.sql`（两个下划线），版本号递增
  - 版本号不能跳跃或重复
- **反例**: `update.sql`、`fix_table.sql`、`V1_init.sql`（单下划线）

#### CHECK-2305 [MAJOR] 迁移文件未纳入 Git 版本控制

- **检测逻辑**: 检查迁移目录是否在 `.gitignore` 中（不应被忽略）
- **说明**: 迁移文件必须和业务代码一起走 Git 流程，确保各环境一致

#### CHECK-2306 [MINOR] 未配置迁移框架的基线版本

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

### 3.5 数据库迭代规则

> 线上数据库变更必须安全、兼容、可监控，避免锁表和服务中断。

#### CHECK-2401 [BLOCKER] DDL 变更未评估锁表风险

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

#### CHECK-2402 [BLOCKER] 字段变更不向后兼容

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

#### CHECK-2403 [BLOCKER] 数据订正未先 SELECT 确认

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

#### CHECK-2404 [MAJOR] 新增字段未设置合理默认值

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

#### CHECK-2405 [MAJOR] 大表变更未分批执行

- **检测逻辑**: 检查对百万级以上大表的 UPDATE/DELETE 是否做了分批处理
- **说明**: 一次性 UPDATE 百万行会长时间锁表，阻塞其他查询

```sql
-- ❌ 危险: 一次更新百万行
UPDATE orders SET status = -1 WHERE status = 0;

-- ✅ 安全: 分批执行，每批 1000 行
UPDATE orders SET status = -1 WHERE status = 0 LIMIT 1000;
-- 循环执行直到 Rows affected = 0
```

#### CHECK-2406 [MAJOR] UPDATE 语句未同步更新 updated_at

- **检测逻辑**: 检查 UPDATE 语句是否包含 `updated_at = NOW()` 或等效设置
- **说明**: 如果表有 `ON UPDATE CURRENT_TIMESTAMP` 则自动更新，否则必须手动设置

#### CHECK-2407 [MAJOR] 缺少数据库变更的审批流程

- **检测逻辑**: 检查是否有 DDL 变更的审批机制
- **推荐流程**:

```
开发编写迁移 SQL → 自测通过 → 提交 Code Review → DBA 审核（大表/高危操作）→ 测试环境验证 → 生产执行
```

#### CHECK-2408 [MINOR] 废弃表/字段未及时清理

- **检测逻辑**: 检查是否存在代码中已无引用但数据库中仍存在的表或字段
- **说明**: 废弃字段建议先重命名（如加 `_deprecated` 后缀），观察一段时间确认无影响后再删除

---

## 四、审查报告模板

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
[按上述输出格式逐项列出]

## MAJOR 问题（强烈建议修复）
[按上述输出格式逐项列出]

## MINOR 问题（建议优化）
[按上述输出格式逐项列出]

## 总结与建议
[1-3 条最关键的改进方向]
```

---

## 五、审查模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **Full** | 19 项维度全量扫描 | 新项目初始化、大版本发布前 |
| **PR** | 仅扫描变更文件涉及的维度 | Pull Request Code Review |
| **Focus** | 指定维度检查 | 专项治理（如安全专项） |
| **Quick** | 仅 BLOCKER 级别 | 快速门禁检查 |

使用方式：
- 默认使用 **PR** 模式
- 用户可通过 "全量审查"、"只看安全" 等表述指定模式
