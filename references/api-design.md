# RESTful 接口设计与参数校验

## RESTful 接口设计

> 用 URL 表示资源，用 HTTP Method 表示操作，返回正确的状态码。

### CHECK-0901 [MAJOR] URL 设计不符合 RESTful

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

### CHECK-0902 [MAJOR] 响应格式不统一

- **检测逻辑**: 检查所有 Controller 方法的返回类型是否使用统一的响应信封
- **标准格式**:

```json
{ "code": "OK",    "data": { ... } }
{ "code": "NOT_FOUND", "message": "...", "data": null }
```

### CHECK-0903 [MAJOR] 列表接口缺少分页

- **检测逻辑**: 检查返回列表数据的接口是否支持分页参数
- **说明**: 无分页的列表接口在数据量增长后会导致性能问题和前端渲染卡顿
- **两种策略**: Offset（`?page=1&size=20`）适合后台管理；Cursor（`?cursor=xxx&size=20`）适合无限滚动

### CHECK-0904 [MINOR] 缺少 API 版本控制

- **检测逻辑**: 检查接口路径中是否包含版本号（如 `/api/v1/`）

---

## 参数校验与 XSS 防范

> 所有接口入参必须校验，永远不信任用户输入。

### CHECK-1001 [BLOCKER] 接口入参未校验

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

### CHECK-1002 [BLOCKER] 请求体 VO 缺少校验注解

- **检测逻辑**: 检查请求 VO/DTO 类的字段是否有 Jakarta Bean Validation 注解
- **常用注解**: `@NotNull`、`@NotBlank`、`@Size`、`@Min`、`@Max`、`@Pattern`、`@Email`

```java
public record CreateOrderRequest(
    @NotNull Long productId,
    @Min(1) @Max(999) Integer quantity,
    @NotBlank @Size(max = 200) String remark
) {}
```

### CHECK-1003 [MAJOR] 文件上传未校验类型和大小

- **检测逻辑**: 检查文件上传接口是否校验了文件类型（MIME type）和文件大小
- **说明**: 防止恶意文件上传

### CHECK-1004 [MAJOR] 输出到前端的内容未转义

- **检测逻辑**: 检查向 HTML 输出的用户生成内容是否做了 XSS 转义
