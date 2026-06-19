---
name: migrating-mvc-content-negotiation
description: >
  Migrates ASP.NET Web API content negotiation and formatters to ASP.NET Core equivalents.
  Converts MediaTypeFormatter subclasses to InputFormatter/OutputFormatter, replaces
  IContentNegotiator with OutputFormatterSelector, and updates formatter registration from
  HttpConfiguration.Formatters to MvcOptions. Use when upgrading Web API projects that define
  custom MediaTypeFormatter classes, configure content negotiation via IContentNegotiator,
  register XML or JSON formatters, use MediaTypeMapping, or need to migrate from Newtonsoft.Json
  to System.Text.Json. Also triggers for conneg migration, formatter pipeline changes, and
  406 Not Acceptable behavior configuration.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET Web API Content Negotiation Migration

## Overview

Migrate Web API content negotiation infrastructure from ASP.NET Framework to ASP.NET Core. The formatter base classes, registration model, and default serializer all changed — custom `MediaTypeFormatter` subclasses must be rewritten against new base classes, and projects relying on XML or Newtonsoft.Json defaults need explicit opt-in.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory formatters and negotiation code
- [ ] Step 2: Configure built-in formatters
- [ ] Step 3: Migrate custom formatters
- [ ] Step 4: Migrate serialization settings
- [ ] Step 5: Update formatter registration
- [ ] Step 6: Remove legacy references
```

### Step 1: Inventory Formatters and Negotiation Code

Search the codebase for content negotiation surface area:

- Classes extending `MediaTypeFormatter` or `BufferedMediaTypeFormatter`
- `IContentNegotiator` implementations
- `config.Formatters` registrations (e.g., `config.Formatters.Add()`, `config.Formatters.Remove()`)
- `MediaTypeMapping` subclasses (`QueryStringMapping`, `UriPathExtensionMapping`, `RequestHeaderMapping`)
- `GlobalConfiguration.Configuration.Formatters.JsonFormatter.SerializerSettings`
- References to `JsonMediaTypeFormatter` or `XmlMediaTypeFormatter`

Record each item and its file location before proceeding.

### Step 2: Configure Built-in Formatters

ASP.NET Core includes only JSON formatting by default. Opt in to additional built-in formatters as needed.

**XML support** — add explicitly if the project used XML content negotiation:

```csharp
builder.Services.AddControllers()
    .AddXmlSerializerFormatters();
```

Use `AddXmlDataContractSerializerFormatters()` instead if the legacy project used `DataContractSerializer`.

**406 Not Acceptable** — Core returns JSON for unknown Accept headers by default. To restore strict negotiation behavior:

```csharp
builder.Services.AddControllers(options =>
{
    options.ReturnHttpNotAcceptable = true;
});
```

**Browser Accept header** — Core respects `*/*` from browsers and returns JSON. To match legacy behavior that returned XML for browsers, add `RespectBrowserAcceptHeader = true` to `MvcOptions`.

### Step 3: Migrate Custom Formatters

Convert each `MediaTypeFormatter` subclass to its ASP.NET Core equivalent. The mapping depends on whether the formatter handles output, input, or both.

#### Class Mapping

| ASP.NET Web API | ASP.NET Core |
|---|---|
| `MediaTypeFormatter` (output) | `TextOutputFormatter` or `OutputFormatter` |
| `MediaTypeFormatter` (input) | `TextInputFormatter` or `InputFormatter` |
| `BufferedMediaTypeFormatter` | `InputFormatter` / `OutputFormatter` (no buffered base) |
| `MediaTypeMapping` | Set `SupportedMediaTypes` on the formatter directly |
| `IContentNegotiator` | `OutputFormatterSelector` (rarely needed) |

#### Before — ASP.NET Web API Custom Formatter

```csharp
public class CsvFormatter : BufferedMediaTypeFormatter
{
    public CsvFormatter()
    {
        SupportedMediaTypes.Add(new MediaTypeHeaderValue("text/csv"));
        SupportedEncodings.Add(new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    public override bool CanReadType(Type type) => false;
    public override bool CanWriteType(Type type) => typeof(IEnumerable).IsAssignableFrom(type);

    public override void WriteToStream(Type type, object value, Stream writeStream, HttpContent content)
    {
        using var writer = new StreamWriter(writeStream);
        foreach (var item in (IEnumerable)value)
        {
            writer.WriteLine(FormatCsvRow(item));
        }
    }
}
```

#### After — ASP.NET Core Custom Formatter

```csharp
public class CsvOutputFormatter : TextOutputFormatter
{
    public CsvOutputFormatter()
    {
        SupportedMediaTypes.Add(MediaTypeHeaderValue.Parse("text/csv"));
        SupportedEncodings.Add(Encoding.UTF8);
    }

    protected override bool CanWriteType(Type? type) =>
        typeof(IEnumerable).IsAssignableFrom(type);

    public override async Task WriteResponseBodyAsync(
        OutputFormatterWriteContext context,
        Encoding selectedEncoding)
    {
        var response = context.HttpContext.Response;
        foreach (var item in (IEnumerable)context.Object!)
        {
            await response.WriteAsync(FormatCsvRow(item), selectedEncoding);
        }
    }
}
```

Key differences in the conversion:

- **Base class**: `BufferedMediaTypeFormatter` → `TextOutputFormatter`. Use `OutputFormatter` for binary formats.
- **Write method**: synchronous `WriteToStream` → async `WriteResponseBodyAsync` with `OutputFormatterWriteContext`.
- **Read method**: synchronous `ReadFromStream` → async `ReadRequestBodyAsync` with `InputFormatterContext`.
- **Encoding**: `SupportedEncodings` API is similar, but `UTF8Encoding` constructor form changes to `Encoding.UTF8`.
- **Media type mappings**: Remove `MediaTypeMapping` subclasses. Add media types directly to `SupportedMediaTypes`.

### Step 4: Migrate Serialization Settings

The default JSON serializer changed from Newtonsoft.Json to System.Text.Json. Evaluate which approach fits the project.

#### Serialization Behavior Comparison

| Behavior | Newtonsoft.Json (Web API default) | System.Text.Json (Core default) |
|---|---|---|
| Property naming | camelCase via `CamelCasePropertyNamesContractResolver` | camelCase via `JsonNamingPolicy.CamelCase` |
| Null handling | Includes nulls | Includes nulls (`DefaultIgnoreCondition = Never`) |
| Case-insensitive read | Off by default | On by default (`PropertyNameCaseInsensitive = true`) |
| Circular references | Handled via `PreserveReferencesHandling` | `ReferenceHandler.Preserve` (opt-in) |
| Missing members | Ignored | Ignored |
| Comments in JSON | Allowed | Rejected (opt-in via `ReadCommentHandling`) |
| Trailing commas | Allowed | Rejected (opt-in via `AllowTrailingCommas`) |
| Number from string | Allowed | Rejected (opt-in via `NumberHandling`) |
| Attribute for property name | `[JsonProperty("name")]` | `[JsonPropertyName("name")]` |
| Custom converter base | `JsonConverter` | `JsonConverter<T>` |

#### Option A: Adopt System.Text.Json (Recommended)

Configure System.Text.Json to match prior behavior where needed:

```csharp
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        options.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.Preserve;
        options.JsonSerializerOptions.ReadCommentHandling = JsonCommentHandling.Skip;
        options.JsonSerializerOptions.AllowTrailingCommas = true;
        options.JsonSerializerOptions.NumberHandling = JsonNumberHandling.AllowReadingFromString;
    });
```

Replace Newtonsoft attributes on model classes:

```csharp
// Before
[JsonProperty("user_name")]
public string UserName { get; set; }

// After
[JsonPropertyName("user_name")]
public string UserName { get; set; }
```

Migrate custom `JsonConverter` implementations to `JsonConverter<T>`:

```csharp
// Before (Newtonsoft)
public class DateOnlyConverter : JsonConverter
{
    public override object ReadJson(JsonReader reader, Type objectType,
        object existingValue, JsonSerializer serializer) { /* ... */ }
    public override void WriteJson(JsonWriter writer, object value,
        JsonSerializer serializer) { /* ... */ }
}

// After (System.Text.Json)
public class DateOnlyConverter : JsonConverter<DateOnly>
{
    public override DateOnly Read(ref Utf8JsonReader reader, Type typeToConvert,
        JsonSerializerOptions options) { /* ... */ }
    public override void Write(Utf8JsonWriter writer, DateOnly value,
        JsonSerializerOptions options) { /* ... */ }
}
```

#### Option B: Keep Newtonsoft.Json (Compatibility)

Install `Microsoft.AspNetCore.Mvc.NewtonsoftJson` and opt in:

```csharp
builder.Services.AddControllers()
    .AddNewtonsoftJson(options =>
    {
        // Carry over existing serializer settings
        options.SerializerSettings.NullValueHandling = NullValueHandling.Ignore;
        options.SerializerSettings.ReferenceLoopHandling = ReferenceLoopHandling.Ignore;
    });
```

Choose this option when the project has many custom `JsonConverter` classes, relies on `JObject`/`JToken` extensively, or when API clients depend on exact Newtonsoft serialization behavior.

### Step 5: Update Formatter Registration

Replace Web API formatter registration with ASP.NET Core equivalents.

#### Before — Web API (WebApiConfig.cs or Startup)

```csharp
config.Formatters.Remove(config.Formatters.XmlFormatter);
config.Formatters.Add(new CsvFormatter());
config.Formatters.JsonFormatter.SerializerSettings.NullValueHandling = NullValueHandling.Ignore;
```

#### After — ASP.NET Core (Program.cs)

```csharp
builder.Services.AddControllers(options =>
{
    options.OutputFormatters.Add(new CsvOutputFormatter());
    options.InputFormatters.Add(new CsvInputFormatter());
})
.AddJsonOptions(options =>
{
    options.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
});
```

Registration mapping:

| Web API | ASP.NET Core |
|---|---|
| `config.Formatters.Add(formatter)` | `options.OutputFormatters.Add(formatter)` / `options.InputFormatters.Add(formatter)` |
| `config.Formatters.Remove(formatter)` | `options.OutputFormatters.RemoveType<T>()` / `options.InputFormatters.RemoveType<T>()` |
| `config.Formatters.Insert(0, formatter)` | `options.OutputFormatters.Insert(0, formatter)` |
| `config.Formatters.JsonFormatter` | `AddJsonOptions()` or `AddNewtonsoftJson()` |
| `config.Formatters.XmlFormatter` | `AddXmlSerializerFormatters()` |

### Step 6: Remove Legacy References

Remove these legacy types and namespaces after migration:

- `System.Net.Http.Formatting` namespace and NuGet package
- `MediaTypeFormatter`, `BufferedMediaTypeFormatter` base classes
- `IContentNegotiator` implementations
- `MediaTypeMapping` subclasses (`QueryStringMapping`, `UriPathExtensionMapping`, `RequestHeaderMapping`)
- `GlobalConfiguration.Configuration.Formatters` references
- `JsonMediaTypeFormatter` and `XmlMediaTypeFormatter` direct references

Verify the project builds without errors and that API responses return correct content types by testing with `Accept: application/json`, `Accept: application/xml`, and any custom media types.

## Success Criteria

- Built-in formatters configured explicitly (XML opt-in, 406 behavior set)
- Custom `MediaTypeFormatter` subclasses converted to `OutputFormatter`/`InputFormatter`
- Serialization configured via `AddJsonOptions()` or `AddNewtonsoftJson()`
- Newtonsoft attributes replaced with System.Text.Json equivalents (if using Option A)
- Formatter registration moved from `config.Formatters` to `MvcOptions`
- No references to `System.Net.Http.Formatting`, `IContentNegotiator`, or `MediaTypeMapping`
- Project builds without errors
