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

## Wire-Contract Gate

Use the project/usage inventory to identify affected hosts, including Framework
consumers of shared serialization libraries.

For ASP.NET Framework-to-Core migrations, changes affecting Framework HTTP
consumers, or unknown host or consumer applicability, the following rules apply.
Before any changes, load `migrating-webapi-odata` and apply its wire-contract
gate, including non-OData endpoints and when this skill is invoked directly.
Run its cheap applicability check first. Require a recorded scoped PASS or
evidence-backed NOT APPLICABLE before executing the automatic workflow below.
If the gate is unavailable or evidence is unknown, STOP.
On STOP, follow the gate's preservation and in-place replanning instructions
instead of changing formatters or serialization. An approved preservation task
is separate from this automatic conversion workflow.

For applications already on ASP.NET Core with inventory evidence of no affected
Framework consumers, skip the Framework-specific gate and migration steps; no
wire-gate PASS is required. Do not infer this from the project's target framework
alone. Complete the Serialization Naming Inventory, preserve the effective source
policy, apply the relevant naming recipe, and compare actual HTTP responses as
described below. Preserve the existing serializer if its behavior cannot be
represented faithfully.

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

#### Serialization Naming Inventory

Before changing formatter or serializer registrations, record the effective
source naming policy, including implicit defaults. No explicit configuration
does not mean camelCase: the default Web API `JsonMediaTypeFormatter` preserves
CLR property names, while ASP.NET Core's System.Text.Json **and Newtonsoft.Json**
integrations default to camelCase. Standalone serializers preserve CLR names by
default; keeping Newtonsoft or testing `JsonConvert.SerializeObject` alone does
not establish HTTP response compatibility.

Distinguish MVC 5 from Web API: MVC 5 `JsonResult` uses `JavaScriptSerializer`
unless the application replaces it. It preserves declared member names, ignores
Newtonsoft `JsonProperty` and `DataMember(Name = ...)`, and honors `ScriptIgnore`.
Inventory those ignored members and any custom `JavaScriptConverter`; do not
infer MVC names from attributes effective only in Web API's Newtonsoft formatter.
For a DTO shared by MVC and Web API, capture both endpoint baselines: the same
`[JsonProperty("user_name")] UserName` can produce `UserName` in MVC and
`user_name` in Web API, with different omitted members.

Reuse the wire-contract baseline when the gate applies; otherwise capture a
source HTTP response baseline. Capture unannotated and explicitly named
properties, nested models, dictionary keys, custom converters/resolvers, and
per-action overrides. Trace `ContractResolver`, `NamingStrategy`, and attribute
settings, including whether explicit names and dictionary keys are rewritten.
If the effective policy or response evidence is unknown, STOP and resolve it;
do not guess or apply a blanket PascalCase fix.

Persist the inventory under `## Wire Compatibility` in the managed task's
`progress-details.md`, with its path referenced in `task.md`; without managed
task state, use `.github/upgrades/wire-compatibility.md`. Carry the record path
into child tasks and read it on resume, including for Core-only scope that skips
the Framework gate.

Within that section, use labeled lines for `Source:`, `Naming policy:`,
`Explicit names:`, `Nested models:`, `Dictionary keys:`, and `Baseline evidence:`.
Give each a concrete finding or evidence-backed absence; use `unknown` for
unresolved fields, not a completed-inventory claim. Keep supporting source
locations and response evidence with these findings.

### Step 2: Configure Built-in Formatters

ASP.NET Core includes only JSON formatting by default. Apply the naming policy
from Step 1 when registering controllers, using Step 4; do not leave the new
web defaults in place pending a later cleanup. Opt in to additional built-in formatters as needed.

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

Choose the serializer by compatibility with the Step 1 baseline, not by the
target .NET version. Retaining Newtonsoft.Json does not retain Web API defaults.
The examples below cover two proven source policies, not universal defaults.
Carry over other effective settings separately; do not introduce null omission
or reference metadata as part of a naming fix.

#### Serialization Behavior Comparison

| Behavior | Newtonsoft.Json (Web API default) | System.Text.Json (Core default) |
|---|---|---|
| Property naming | Preserves CLR names unless a resolver/naming strategy changes them | camelCase (web default, not standalone default) |
| Null handling | Includes nulls | Includes nulls (`DefaultIgnoreCondition = Never`) |
| Case-insensitive read | On by default | On by default (`PropertyNameCaseInsensitive = true`) |
| Circular references | Handled via `PreserveReferencesHandling` | `ReferenceHandler.Preserve` (opt-in) |
| Missing members | Ignored | Ignored |
| Comments in JSON | Allowed | Rejected (opt-in via `ReadCommentHandling`) |
| Trailing commas | Allowed | Rejected (opt-in via `AllowTrailingCommas`) |
| Number from string | Allowed | Allowed by web defaults (`AllowReadingFromString`) |
| Attribute for property name | `[JsonProperty("name")]` | `[JsonPropertyName("name")]` |
| Custom converter base | `JsonConverter` | `JsonConverter<T>` |

#### Option A: Adopt System.Text.Json

For a proven source policy that preserves CLR property names and dictionary keys:

```csharp
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
        options.JsonSerializerOptions.DictionaryKeyPolicy = null;
    });
```

For a proven camelCase source policy that leaves explicit names and dictionary
keys unchanged, use this alternative, not the CLR-name example:

```csharp
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.DictionaryKeyPolicy = null;
    });
```

For custom policies, map the effective behavior rather than substituting one of
these examples. `[JsonPropertyName]` overrides System.Text.Json naming policies;
Newtonsoft resolvers that rewrite explicit names require additional mapping.
Preserve the existing serializer if converters, resolver rules, or attributes
cannot be represented faithfully; do not silently ignore them.

Replace Newtonsoft name attributes only when the source serializer actually honored them:

```csharp
// Before
[JsonProperty("user_name")]
public string UserName { get; set; }

// After
[JsonPropertyName("user_name")]
public string UserName { get; set; }
```

Do not activate an inert MVC 5 attribute by translating it to `JsonPropertyName`,
or treat `DataMember(Name = ...)` as an effective MVC name. For shared DTOs with
different source contracts, use an endpoint-specific projection/DTO or an explicitly
configured `JsonTypeInfo` resolver/converter that reproduces each contract.
Setting `PropertyNamingPolicy` alone, including plain options passed to `Json(data, options)`,
does not override `JsonPropertyName`. Preserve `ScriptIgnore` omissions too: map to
System.Text.Json `JsonIgnore` only where that omission is correct for every affected
endpoint, otherwise keep it endpoint-specific. Verify both names and omitted members
through both HTTP endpoints before changing a shared model.

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

Install `Microsoft.AspNetCore.Mvc.NewtonsoftJson` and opt in. Its default resolver
uses `CamelCaseNamingStrategy`, unlike the original Web API formatter. For a
proven source policy that preserves CLR property names and dictionary keys:

```csharp
builder.Services.AddControllers()
    .AddNewtonsoftJson(options =>
    {
        options.SerializerSettings.ContractResolver =
            new Newtonsoft.Json.Serialization.DefaultContractResolver();
    });
```

For a proven camelCase source policy that leaves explicit names and dictionary
keys unchanged:

```csharp
builder.Services.AddControllers()
    .AddNewtonsoftJson(options =>
    {
        options.SerializerSettings.ContractResolver =
            new Newtonsoft.Json.Serialization.DefaultContractResolver
            {
                NamingStrategy = new Newtonsoft.Json.Serialization.CamelCaseNamingStrategy
                {
                    ProcessDictionaryKeys = false,
                    OverrideSpecifiedNames = false
                }
            };
    });
```

If the source uses a custom resolver or other naming-strategy settings, port
that resolver and its settings instead of replacing it with either example.
In particular, `CamelCasePropertyNamesContractResolver` also rewrites dictionary
keys and explicit names; it is not equivalent to the second example.
Do not add property-name attributes to every DTO to mask a global policy change.

Choose this option when the project has many custom `JsonConverter` classes, relies on `JObject`/`JToken` extensively, or when API clients depend on exact Newtonsoft serialization behavior.

### Step 5: Update Formatter Registration

Replace Web API formatter registration with ASP.NET Core equivalents.
Compose these registrations with the Step 4 naming configuration; this partial
example is for **Option A only** and does not replace that naming configuration.
For **Option B**, keep `AddNewtonsoftJson` and carry the source settings into
`SerializerSettings`, including `NullValueHandling.Ignore` from the example below;
do not use `AddJsonOptions` to configure a retained Newtonsoft serializer.

#### Before — Web API (WebApiConfig.cs or Startup)

```csharp
config.Formatters.Remove(config.Formatters.XmlFormatter);
config.Formatters.Add(new CsvFormatter());
config.Formatters.JsonFormatter.SerializerSettings.NullValueHandling = NullValueHandling.Ignore;
```

#### After — ASP.NET Core, Option A Only (Program.cs)

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

Compare original and migrated JSON bodies through the actual HTTP/MVC formatter
pipeline, not just standalone serializers or controller return objects. Include
unannotated and explicitly named properties, nested models, dictionary keys,
and each custom/per-action policy from the baseline. Assert exact property names
without case-insensitive comparison or normalization. If contract evidence is
missing or comparison fails, do not claim compatibility or move traffic.

## Success Criteria

- Built-in formatters configured explicitly (XML opt-in, 406 behavior set)
- Custom `MediaTypeFormatter` subclasses converted to `OutputFormatter`/`InputFormatter`
- Serialization configured via `AddJsonOptions()` or `AddNewtonsoftJson()`
- Effective source naming policy preserved, including implicit defaults; response-pipeline comparisons match the baseline
- Newtonsoft attributes replaced with System.Text.Json equivalents (if using Option A)
- Formatter registration moved from `config.Formatters` to `MvcOptions`
- No references to `System.Net.Http.Formatting`, `IContentNegotiator`, or `MediaTypeMapping`
- Project builds without errors
