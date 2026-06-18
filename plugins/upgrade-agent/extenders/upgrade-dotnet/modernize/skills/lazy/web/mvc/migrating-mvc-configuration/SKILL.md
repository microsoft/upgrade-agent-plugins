---
name: migrating-mvc-configuration
description: >
  Migrates ASP.NET Framework Web.config configuration to ASP.NET Core appsettings.json and
  IConfiguration/IOptions patterns. Covers appSettings, connectionStrings, custom config sections,
  environment-specific transforms, and encrypted config. Use when upgrading projects that use
  ConfigurationManager.AppSettings, ConfigurationManager.ConnectionStrings, custom
  IConfigurationSectionHandler implementations, Web.Debug.config/Web.Release.config transforms,
  or encrypted config sections. Also triggers for "migrate Web.config", "convert appSettings to
  appsettings.json", "replace ConfigurationManager", "migrate connection strings", or "convert
  config transforms".
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET Web.config Configuration Migration

Migrate `Web.config` XML configuration to ASP.NET Core's `appsettings.json` and `IConfiguration` system. The new configuration model is fundamentally different: it uses layered JSON files instead of XML transforms, environment variables override file values, and strongly-typed access replaces string-keyed lookups. Secrets must move out of config files entirely.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory configuration usage
- [ ] Step 2: Create appsettings.json structure
- [ ] Step 3: Migrate appSettings and connectionStrings
- [ ] Step 4: Convert custom config sections to IOptions<T>
- [ ] Step 5: Replace config transforms with environment files
- [ ] Step 6: Migrate secrets to secure storage
- [ ] Step 7: Remove Web.config configuration code
```

### Step 1: Inventory Configuration Usage

Search the project for all configuration access patterns and record what exists:

- `ConfigurationManager.AppSettings["key"]` calls
- `ConfigurationManager.ConnectionStrings["name"]` calls
- Custom `<configSections>` declarations in `Web.config`
- `ConfigurationElementCollection` or `IConfigurationSectionHandler` implementations
- `Web.Debug.config`, `Web.Release.config`, or other transform files
- `<EncryptedData>` blocks or `aspnet_regiis -pe` usage
- `<machineKey>` elements

Classify each item by assessment signal: `UsesWebConfigAppSettings`, `UsesConnectionStrings`, `UsesCustomConfigSections`, `UsesConfigTransforms`, `UsesEncryptedConfig`.

### Step 2: Create appsettings.json Structure

Create `appsettings.json` at the project root. Transfer key-value pairs from `<appSettings>` and connection strings from `<connectionStrings>` into a structured JSON format.

**Before** (`Web.config`):
```xml
<configuration>
  <appSettings>
    <add key="SiteTitle" value="My Application" />
    <add key="MaxRetries" value="3" />
    <add key="FeatureFlags:EnableNewUI" value="true" />
  </appSettings>
  <connectionStrings>
    <add name="DefaultConnection"
         connectionString="Server=.;Database=MyDb;Integrated Security=True"
         providerName="System.Data.SqlClient" />
  </connectionStrings>
</configuration>
```

**After** (`appsettings.json`):
```json
{
  "SiteTitle": "My Application",
  "MaxRetries": 3,
  "FeatureFlags": {
    "EnableNewUI": true
  },
  "ConnectionStrings": {
    "DefaultConnection": "Server=.;Database=MyDb;Integrated Security=True"
  }
}
```

Group related flat keys into nested objects where the original key used colon or dot separators. Place connection strings under the `ConnectionStrings` section because `GetConnectionString()` expects that location.

### Step 3: Migrate AppSettings and ConnectionStrings Access

Replace all `ConfigurationManager` calls with `IConfiguration` equivalents. Inject `IConfiguration` via constructor injection where needed.

**Before:**
```csharp
using System.Configuration;

public class MyService
{
    public string GetTitle()
    {
        return ConfigurationManager.AppSettings["SiteTitle"];
    }

    public string GetConnectionString()
    {
        return ConfigurationManager.ConnectionStrings["DefaultConnection"].ConnectionString;
    }
}
```

**After:**
```csharp
using Microsoft.Extensions.Configuration;

public class MyService
{
    private readonly IConfiguration _configuration;

    public MyService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public string GetTitle()
    {
        return _configuration["SiteTitle"];
    }

    public string GetConnectionString()
    {
        return _configuration.GetConnectionString("DefaultConnection");
    }
}
```

For classes that read many related settings, prefer the strongly-typed `IOptions<T>` pattern over individual key lookups — see Step 4.

#### ⚠️ AttachDbFilename and |DataDirectory| Are Not Supported

If the original `Web.config` uses `AttachDbFilename` with the `|DataDirectory|` substitution token, the connection string **must be rewritten** for ASP.NET Core.

**Why it fails:**
- The `|DataDirectory|` token is not supported (no `AppDomain.SetData` in ASP.NET Core)
- Attached database file patterns cause authentication and connection pooling issues with EF Core

**Original pattern (will fail):**
```xml
<!-- Web.config -->
<connectionStrings>
  <add name="DefaultConnection" 
       connectionString="Data Source=(LocalDB)\MSSQLLocalDB;AttachDbFilename=|DataDirectory|\MyApp.mdf;Integrated Security=True"
       providerName="System.Data.SqlClient" />
</connectionStrings>
```

**Required changes:**
1. Remove `AttachDbFilename=...` from the connection string
2. Remove the `|DataDirectory|` token
3. Specify the database using `Initial Catalog` or `Database` instead

**Migration options** (choose based on the original application's database setup):

- **If the app used LocalDB with an attached file**, either:
  - Switch to LocalDB without file attachment: `Data Source=(LocalDB)\\MSSQLLocalDB;Initial Catalog=MyApp;Integrated Security=True`
  - Or switch to a full SQL Server instance: `Server=localhost;Database=MyApp;Integrated Security=True;TrustServerCertificate=True`

- **If the app deployed with SQL Server Express or full SQL Server**, use the explicit server and database name pattern

The key decision is whether to continue using LocalDB (typically development scenarios) or switch to SQL Server (typically required for production, load balancing, or multi-user scenarios). This choice should match the deployment model of the original application.

### Step 4: Convert Custom Config Sections to IOptions&lt;T&gt;

Custom config sections (`IConfigurationSectionHandler`, `ConfigurationSection`, `ConfigurationElementCollection`) have no direct equivalent. Convert them to POCO classes bound from JSON via `IOptions<T>`.

**Before** (`Web.config` + custom section class):
```xml
<configuration>
  <configSections>
    <section name="mailSettings" type="MyApp.MailConfigSection, MyApp" />
  </configSections>
  <mailSettings smtpServer="mail.example.com" port="587" enableSsl="true">
    <recipients>
      <add address="admin@example.com" />
      <add address="alerts@example.com" />
    </recipients>
  </mailSettings>
</configuration>
```

**After** (`appsettings.json` + POCO + registration):
```json
{
  "MailSettings": {
    "SmtpServer": "mail.example.com",
    "Port": 587,
    "EnableSsl": true,
    "Recipients": [
      "admin@example.com",
      "alerts@example.com"
    ]
  }
}
```

```csharp
public class MailSettings
{
    public string SmtpServer { get; set; }
    public int Port { get; set; }
    public bool EnableSsl { get; set; }
    public List<string> Recipients { get; set; } = new();
}
```

Register in `Program.cs`:
```csharp
builder.Services.Configure<MailSettings>(
    builder.Configuration.GetSection("MailSettings"));
```

Inject as `IOptions<MailSettings>` (singleton snapshot), `IOptionsSnapshot<MailSettings>` (scoped, reloads per request), or `IOptionsMonitor<MailSettings>` (live reload with change notifications). Use `IOptions<T>` as the default unless the application needs runtime config reload.

Delete the old `ConfigurationSection`, `ConfigurationElement`, and `ConfigurationElementCollection` classes after migration. Convert `ConfigurationElementCollection` patterns (XML element lists) to JSON arrays bound to `List<T>` or array properties.

### Step 5: Replace Config Transforms with Environment Files

ASP.NET Core has no equivalent to `xdt:Transform` syntax. Instead, it layers environment-specific JSON files over the base file. The environment name comes from the `ASPNETCORE_ENVIRONMENT` variable, not from build configuration.

**Before** (transform files):
```
Web.config                 ← base
Web.Debug.config           ← xdt:Transform for Debug builds
Web.Release.config         ← xdt:Transform for Release builds
Web.Staging.config         ← xdt:Transform for Staging
```

**After** (environment files):
```
appsettings.json                  ← base (all environments)
appsettings.Development.json      ← overrides for local dev
appsettings.Staging.json          ← overrides for staging
appsettings.Production.json       ← overrides for production
```

Later files override earlier ones. `appsettings.{Environment}.json` values replace matching keys from `appsettings.json`. Environment variables override both. This means the loading order is:

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. Environment variables
4. Command-line arguments

Move transform-specific values into the appropriate environment file. Do not replicate the full base config in each environment file — include only the keys that differ.

### Step 6: Migrate Secrets to Secure Storage

**This step is critical for security.** Connection strings with passwords, API keys, and any sensitive values must not remain in `appsettings.json` or be committed to source control.

**Development environment** — use User Secrets:
```bash
dotnet user-secrets init
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Server=.;Database=MyDb;User=sa;Password=secret"
```

User Secrets are stored outside the project directory and override `appsettings.json` in development.

**Production environment** — use environment variables or a secrets manager:
- Environment variables: set `ConnectionStrings__DefaultConnection` (double underscore replaces colon for hierarchical keys)
- Azure Key Vault: add `Azure.Extensions.AspNetCore.Configuration.Secrets` package and call `builder.Configuration.AddAzureKeyVault()`
- AWS Secrets Manager or similar vault services

**`machineKey` migration**: ASP.NET Core replaces `<machineKey>` with the Data Protection API. The key management model is completely different — keys are auto-rotated and stored per-application by default. If multiple applications share a `machineKey` for cookie or token validation, configure a shared Data Protection key ring:

```csharp
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(@"\\server\share\keys"))
    .SetApplicationName("SharedAppName");
```

**Encrypted config sections**: If `Web.config` contains `<EncryptedData>` blocks (from `aspnet_regiis -pe`), decrypt the values first, then migrate them to User Secrets or a vault. There is no equivalent to `aspnet_regiis` in ASP.NET Core.

### Step 7: Remove Web.config Configuration Code

After all configuration has been migrated:

- Remove `using System.Configuration` statements from all files
- Remove `ConfigurationManager` references (search for `ConfigurationManager.AppSettings` and `ConfigurationManager.ConnectionStrings`)
- Delete custom `ConfigurationSection`, `ConfigurationElement`, and `ConfigurationElementCollection` classes
- Delete `Web.Debug.config`, `Web.Release.config`, and other transform files
- Remove the `System.Configuration.ConfigurationManager` NuGet package reference if present
- Remove `<configSections>` declarations from `Web.config` (or the entire `Web.config` if no other sections remain that IIS requires)

Verify the project builds and all configuration values load correctly at runtime.

## Configuration Source Ordering Differences

The config source priority is opposite to `Web.config` intuition. In ASP.NET Framework, `Web.config` is the final authority. In ASP.NET Core, environment variables and command-line arguments override JSON files. Account for this when migrating code that assumes `Web.config` values cannot be overridden.

> **Related skill:** For migrating `Global.asax` startup code that initializes configuration, see `migrating-global-asax`.

## Success Criteria

- `appsettings.json` contains all non-secret settings from `Web.config`
- Environment-specific files replace all config transforms
- No `ConfigurationManager.AppSettings` or `ConfigurationManager.ConnectionStrings` calls remain
- Custom config section classes replaced with POCOs and `IOptions<T>` registration
- Secrets stored in User Secrets (dev) or environment variables/vault (prod) — not in committed files
- `machineKey` replaced with Data Protection API configuration
- No `System.Configuration` using statements remain
- Project builds without errors
