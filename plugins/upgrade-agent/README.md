# Upgrade Plugin

AI-powered assistance for upgrading and modernizing applications. This plugin adds the **upgrade** agent to your Copilot CLI.

## Installation

Add the marketplace, then install the plugin:

```
/plugin marketplace add microsoft/upgrade-agent-plugins
/plugin install upgrade-agent@upgrade-agent-plugins
```

## Usage

Use `/agent` to select **upgrade**, then enter your prompt:

```text
upgrade my project to .NET 10
```

The agent guides you through a structured workflow:

1. **Assessment** — analyzes your project and identifies what needs to change
2. **Planning** — creates a step-by-step upgrade plan
3. **Execution** — applies the changes using specialized tools

## MCP Server

The plugin includes an MCP server (Upgrade) that provides upgrade and analysis tools. It starts automatically when the upgrade agent is invoked — no manual configuration needed.

## Plugin Structure

```
upgrade-agent/
├── agents/
│   └── upgrade.agent.md
├── extenders/
│   └── upgrade-dotnet/
│       ├── upgrade/
│       │   └── skills/
│       │       ├── lazy/
│       │       │   ├── cloud/
│       │       │   │   ├── migrating-azure-functions-startup/
│       │       │   │   │   └── SKILL.md
│       │       │   │   └── migrating-azure-functions-to-v2/
│       │       │   │       └── SKILL.md
│       │       │   ├── common/
│       │       │   │   ├── building-projects/
│       │       │   │   │   ├── references/
│       │       │   │   │   │   └── error-codes.md
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── converting-to-cpm/
│       │       │   │   │   ├── references/
│       │       │   │   │   │   ├── audit-complexities.md
│       │       │   │   │   │   ├── baseline-comparison.md
│       │       │   │   │   │   ├── directory-packages-props.md
│       │       │   │   │   │   ├── msbuild-property-handling.md
│       │       │   │   │   │   └── validation-and-errors.md
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── converting-to-sdk-style/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── managing-legacy-dotnet-packages/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── managing-package-references/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── managing-target-frameworks/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-csharp-nullable-references/
│       │       │   │   │   ├── references/
│       │       │   │   │   │   ├── aspnet-core.md
│       │       │   │   │   │   ├── breaking-changes.md
│       │       │   │   │   │   ├── ef-core.md
│       │       │   │   │   │   └── nullable-attributes.md
│       │       │   │   │   ├── scripts/
│       │       │   │   │   │   └── Get-NullableReadiness.ps1
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── modernizing-csharp-version/
│       │       │   │   │   ├── csharp-10.md
│       │       │   │   │   ├── csharp-11.md
│       │       │   │   │   ├── csharp-12.md
│       │       │   │   │   ├── csharp-13.md
│       │       │   │   │   ├── csharp-14.md
│       │       │   │   │   ├── csharp-15.md
│       │       │   │   │   ├── csharp-7.md
│       │       │   │   │   ├── csharp-8.md
│       │       │   │   │   ├── csharp-9.md
│       │       │   │   │   ├── dotnet-format-rules.md
│       │       │   │   │   └── SKILL.md
│       │       │   │   └── modifying-project-properties/
│       │       │   │       └── SKILL.md
│       │       │   ├── data/
│       │       │   │   ├── migrating-edmx-to-code-first/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-ef-dbcontext/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-ef6-code-first-to-ef-core/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-linq-to-sql-to-ef-core/
│       │       │   │   │   ├── references/
│       │       │   │   │   │   ├── concurrency-and-change-tracking.md
│       │       │   │   │   │   ├── datacontext-to-dbcontext.md
│       │       │   │   │   │   ├── entity-mapping-conversion.md
│       │       │   │   │   │   ├── query-translation-gotchas.md
│       │       │   │   │   │   ├── relationship-migration.md
│       │       │   │   │   │   └── stored-procedure-migration.md
│       │       │   │   │   └── SKILL.md
│       │       │   │   └── migrating-to-microsoft-data-sqlclient/
│       │       │   │       └── SKILL.md
│       │       │   ├── desktop/
│       │       │   │   └── winforms/
│       │       │   │       ├── building-winforms-applications/
│       │       │   │       │   ├── references/
│       │       │   │       │   │   ├── enhancements/
│       │       │   │       │   │   │   ├── async-apis.md
│       │       │   │       │   │   │   └── dark-mode.md
│       │       │   │       │   │   └── detailed-guide.md
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── creating-winforms-custom-controls/
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── managing-winforms-async-apis/
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── managing-winforms-data-binding/
│       │       │   │       │   ├── references/
│       │       │   │       │   │   └── detailed-guide.md
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── managing-winforms-designer-code/
│       │       │   │       │   ├── references/
│       │       │   │       │   │   └── detailed-guide.md
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── managing-winforms-high-dpi-layout/
│       │       │   │       │   ├── references/
│       │       │   │       │   │   └── detailed-guide.md
│       │       │   │       │   └── SKILL.md
│       │       │   │       ├── managing-winforms-mvvm/
│       │       │   │       │   ├── references/
│       │       │   │       │   │   └── detailed-guide.md
│       │       │   │       │   └── SKILL.md
│       │       │   │       └── managing-winforms-rendering/
│       │       │   │           ├── references/
│       │       │   │           │   └── detailed-guide.md
│       │       │   │           └── SKILL.md
│       │       │   ├── libraries/
│       │       │   │   ├── integrating-autofac-with-dotnet/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-adal-to-msal/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-aspnet-signalr/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-autofac-to-dotnet-di/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-azure-keyvault/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-azure-servicebus/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-azure-storage/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-bond-interfaces/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-cosmosdb-bulk-executor/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-cryptography-namespaces/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-data-edm-to-odata/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-data-odata-to-odata-core/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-data-services-client/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-documentdb-to-cosmos/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-newtonsoft-to-system-text-json/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-owin-cookie-auth/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-owin-oauth-to-jwt/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-owin-openid-connect/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-powershell-sdk/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-razorengine-to-razorlight/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-semantic-kernel-to-agents/
│       │       │   │   │   ├── references/
│       │       │   │   │   │   ├── api-mappings.md
│       │       │   │   │   │   └── provider-patterns.md
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-spa-services-to-spa-proxy/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-system-spatial/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-to-msmq-messaging/
│       │       │   │   │   └── SKILL.md
│       │       │   │   ├── migrating-webapi-cors/
│       │       │   │   │   └── SKILL.md
│       │       │   │   └── migrating-webapi-odata/
│       │       │   │       └── SKILL.md
│       │       │   └── web/
│       │       │       ├── aspnet/
│       │       │       │   └── migrating-global-asax/
│       │       │       │       └── SKILL.md
│       │       │       ├── mvc/
│       │       │       │   ├── migrating-aspnet-framework-to-core/
│       │       │       │   │   ├── side-by-side.md
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-aspnet-identity/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-authentication/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-bundling/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-configuration/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-content-negotiation/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-controllers/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-dependency-injection/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-filters/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-http-pipeline/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-httpcontext/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-logging/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-model-binding/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-razor-views/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-routing/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-session-state/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-static-files/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-system-web-adapters/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-mvc-validation/
│       │       │       │   │   └── SKILL.md
│       │       │       │   ├── migrating-owin-to-aspnet-core/
│       │       │       │   │   └── SKILL.md
│       │       │       │   └── scaffolding-yarp-proxy-project/
│       │       │       │       ├── templates/
│       │       │       │       │   ├── mvc/
│       │       │       │       │   │   ├── Properties/
│       │       │       │       │   │   │   └── launchSettings.json
│       │       │       │       │   │   ├── appsettings.Development.json
│       │       │       │       │   │   ├── appsettings.json
│       │       │       │       │   │   ├── Program.cs
│       │       │       │       │   │   └── ProjectName.csproj
│       │       │       │       │   └── webapi/
│       │       │       │       │       ├── Properties/
│       │       │       │       │       │   └── launchSettings.json
│       │       │       │       │       ├── appsettings.Development.json
│       │       │       │       │       ├── appsettings.json
│       │       │       │       │       ├── Program.cs
│       │       │       │       │       └── ProjectName.csproj
│       │       │       │       ├── scaffold-project.ps1
│       │       │       │       └── SKILL.md
│       │       │       ├── wcf/
│       │       │       │   └── migrating-wcf-to-corewcf/
│       │       │       │       └── SKILL.md
│       │       │       └── webforms/
│       │       │           ├── managing-blazor-server-authentication/
│       │       │           │   ├── references/
│       │       │           │   │   ├── cookie-auth-pattern.md
│       │       │           │   │   └── endpoint-templates.md
│       │       │           │   └── SKILL.md
│       │       │           ├── managing-blazor-server-data-access/
│       │       │           │   ├── references/
│       │       │           │   │   └── session-state-patterns.md
│       │       │           │   └── SKILL.md
│       │       │           └── migrating-webforms-to-blazor-server/
│       │       │               ├── references/
│       │       │               │   ├── ajax-toolkit.md
│       │       │               │   ├── code-transforms.md
│       │       │               │   ├── control-reference.md
│       │       │               │   └── markup-transforms.md
│       │       │               └── SKILL.md
│       │       └── scenarios/
│       │           ├── aspire-integration/
│       │           │   ├── aspire-cli.md
│       │           │   ├── assessment.md
│       │           │   ├── execution.md
│       │           │   └── SKILL.md
│       │           ├── aspire-version-upgrade/
│       │           │   ├── assessment.md
│       │           │   ├── breaking-changes.md
│       │           │   ├── execution.md
│       │           │   └── SKILL.md
│       │           ├── azure-functions-upgrade/
│       │           │   └── SKILL.md
│       │           ├── azure-migrate/
│       │           │   └── SKILL.md
│       │           ├── dotnet-framework-version-upgrade/
│       │           │   ├── assessment.md
│       │           │   ├── execution.md
│       │           │   ├── planning.md
│       │           │   └── SKILL.md
│       │           ├── dotnet-version-upgrade/
│       │           │   ├── breakdown-hints/
│       │           │   │   ├── common.md
│       │           │   │   ├── framework-migration.md
│       │           │   │   ├── framework-web-migration.md
│       │           │   │   └── test.md
│       │           │   ├── planning-rules/
│       │           │   │   ├── framework-migration.md
│       │           │   │   └── modern-upgrade.md
│       │           │   ├── strategies/
│       │           │   │   ├── all-at-once.md
│       │           │   │   ├── bottom-up.md
│       │           │   │   └── top-down.md
│       │           │   ├── upgrade-options/
│       │           │   │   ├── binding-redirects.md
│       │           │   │   ├── configuration-migration.md
│       │           │   │   ├── dependency-injection.md
│       │           │   │   ├── entity-framework.md
│       │           │   │   ├── logging-framework.md
│       │           │   │   ├── nullable-reference-types.md
│       │           │   │   ├── package-management.md
│       │           │   │   ├── project-approach.md
│       │           │   │   ├── strategy.md
│       │           │   │   ├── system-web-adapters.md
│       │           │   │   ├── unsupported-api-handling.md
│       │           │   │   ├── unsupported-packages.md
│       │           │   │   ├── upgrade-options-index.md
│       │           │   │   └── windows-native-apis.md
│       │           │   ├── assessment.md
│       │           │   ├── confirm-options-mcp.md
│       │           │   ├── execution.md
│       │           │   ├── planning.md
│       │           │   ├── post-completion.md
│       │           │   └── SKILL.md
│       │           ├── newtonsoft-json-migration/
│       │           │   └── SKILL.md
│       │           ├── nuget-package-upgrade/
│       │           │   ├── upgrade-options/
│       │           │   │   └── version-reconciliation.md
│       │           │   ├── assessment.md
│       │           │   ├── execution.md
│       │           │   ├── planning.md
│       │           │   └── SKILL.md
│       │           ├── sdk-style-conversion/
│       │           │   └── SKILL.md
│       │           ├── semantic-kernel-to-agents-framework/
│       │           │   └── SKILL.md
│       │           ├── sqlclient-migration/
│       │           │   └── SKILL.md
│       │           ├── vssdk-sdk-style-conversion/
│       │           │   ├── references/
│       │           │   │   └── vssdk-project-format.md
│       │           │   └── SKILL.md
│       │           ├── webforms-to-blazor-upgrade/
│       │           │   └── SKILL.md
│       │           └── winforms-feature-adoption/
│       │               ├── execution.md
│       │               ├── feature-selection.md
│       │               ├── planning.md
│       │               └── SKILL.md
│       └── upgrade-extension.json
├── extensions/
│   └── modernize-dashboard/
├── hooks/
│   └── scripts/
│       ├── track-telemetry.ps1
│       └── track-telemetry.sh
├── upgrade/
│   └── skills/
│       ├── generic/
│       │   └── creating-skills/
│       │       ├── references/
│       │       │   ├── anthropic-best-practices.md
│       │       │   ├── quality-checklist.md
│       │       │   └── validation-rules.md
│       │       ├── scripts/
│       │       │   ├── validate_skill.ps1
│       │       │   └── validate_skill.sh
│       │       ├── templates/
│       │       │   └── SKILL-TEMPLATE.md
│       │       └── SKILL.md
│       └── system/
│           ├── branch-sync/
│           │   └── SKILL.md
│           ├── generate-report/
│           │   └── SKILL.md
│           ├── plan-generation/
│           │   └── SKILL.md
│           ├── post-scenario-completion/
│           │   └── SKILL.md
│           ├── scenario-discovery/
│           │   └── SKILL.md
│           ├── scenario-initialization/
│           │   └── SKILL.md
│           ├── state-management/
│           │   └── SKILL.md
│           ├── sub-agent-delegation/
│           │   └── SKILL.md
│           ├── task-execution/
│           │   └── SKILL.md
│           ├── tasks-consistency/
│           │   └── SKILL.md
│           ├── token-usage-prediction/
│           │   └── SKILL.md
│           └── user-interaction/
│               └── SKILL.md
├── hooks.json
└── plugin.json
```

## Requirements

- .NET SDK 10.0 or later

## Links

- [Source](https://github.com/microsoft/upgrade-agent-plugins)
