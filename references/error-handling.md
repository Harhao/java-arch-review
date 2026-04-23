# 错误处理

> 不将设计方案之外的异常展示给用户。

## CHECK-0501 [BLOCKER] 缺少全局异常处理器

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

## CHECK-0502 [BLOCKER] 5xx 错误暴露堆栈信息给前端

- **检测逻辑**: 检查全局异常处理器中，未预期异常是否返回了 `e.getMessage()` 或完整堆栈
- **说明**: 堆栈信息包含内部实现细节，暴露给前端是安全风险

## CHECK-0503 [MAJOR] 缺少统一的业务异常体系

- **检测逻辑**: 检查是否定义了 BizException 基类及常见子类（NotFoundException、ForbiddenException 等）
- **说明**: 每种错误情况应有明确的错误码和 HTTP 状态码

## CHECK-0504 [MAJOR] HTTP 状态码使用不当

- **检测逻辑**: 检查 Controller 返回的 HTTP 状态码是否与语义匹配
  - 404: 资源不存在
  - 403: 无权限
  - 409: 资源冲突
  - 不应所有错误都返回 200 + 错误码
