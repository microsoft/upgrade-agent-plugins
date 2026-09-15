# Scoped Logging with Correlation IDs

Framework apps that used `HttpContext.Current.Items` to store correlation IDs should switch to `ILogger` scopes:

```csharp
using (_logger.BeginScope(new Dictionary<string, object>
{
    ["CorrelationId"] = context.Request.Headers["X-Correlation-Id"].FirstOrDefault()
        ?? Guid.NewGuid().ToString()
}))
{
    await _next(context);
}
```
