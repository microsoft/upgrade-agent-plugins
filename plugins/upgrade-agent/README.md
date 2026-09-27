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
│   ├── assessor.agent.md
│   ├── branch-sync.agent.md
│   ├── break-glass.agent.md
│   ├── build-validator.agent.md
│   ├── code-reviewer.agent.md
│   ├── dotnet-version-assessor.agent.md
│   ├── dotnet-version-estimator.agent.md
│   ├── dotnet-version-scenario-initializer.agent.md
│   ├── error-fixer.agent.md
│   ├── jsts-dependabot-validation.agent.md
│   ├── jsts-playwright-spec-author.agent.md
│   ├── planner.agent.md
│   ├── report-generator.agent.md
│   ├── scenario-discovery.agent.md
│   ├── scenario-initializer.agent.md
│   ├── task-breaker.agent.md
│   ├── task-executor.agent.md
│   ├── terminal-executor.agent.md
│   └── upgrade.agent.md
├── assets/
│   └── preview.png
├── com.github.copilot/
│   └── extensions/
│       └── upgrade-agent-dashboard/
├── hooks/
│   └── scripts/
│       ├── track-telemetry.ps1
│       └── track-telemetry.sh
├── upgrade/
│   ├── dotnet/
│   │   ├── skills/
│   │   │   ├── lazy/
│   │   │   │   ├── cloud/
│   │   │   │   │   ├── migrating-azure-functions-startup/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── migrating-azure-functions-to-v2/
│   │   │   │   │       └── SKILL.md
│   │   │   │   ├── common/
│   │   │   │   │   ├── building-projects/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   └── error-codes.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── converting-to-cpm/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── audit-complexities.md
│   │   │   │   │   │   │   ├── baseline-comparison.md
│   │   │   │   │   │   │   ├── directory-packages-props.md
│   │   │   │   │   │   │   ├── msbuild-property-handling.md
│   │   │   │   │   │   │   └── validation-and-errors.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── converting-to-sdk-style/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── managing-legacy-dotnet-packages/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── managing-package-references/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── managing-target-frameworks/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-csharp-nullable-references/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── aspnet-core.md
│   │   │   │   │   │   │   ├── breaking-changes.md
│   │   │   │   │   │   │   ├── ef-core.md
│   │   │   │   │   │   │   └── nullable-attributes.md
│   │   │   │   │   │   ├── scripts/
│   │   │   │   │   │   │   └── Get-NullableReadiness.ps1
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── modernizing-csharp-version/
│   │   │   │   │   │   ├── csharp-10.md
│   │   │   │   │   │   ├── csharp-11.md
│   │   │   │   │   │   ├── csharp-12.md
│   │   │   │   │   │   ├── csharp-13.md
│   │   │   │   │   │   ├── csharp-14.md
│   │   │   │   │   │   ├── csharp-15.md
│   │   │   │   │   │   ├── csharp-7.md
│   │   │   │   │   │   ├── csharp-8.md
│   │   │   │   │   │   ├── csharp-9.md
│   │   │   │   │   │   ├── dotnet-format-rules.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── modifying-project-properties/
│   │   │   │   │       └── SKILL.md
│   │   │   │   ├── data/
│   │   │   │   │   ├── managing-shared-database-schema/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   └── worked-example.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-edmx-to-code-first/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-ef-dbcontext/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-ef6-code-first-to-ef-core/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   └── cutover-teardown.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-linq-to-sql-to-ef-core/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── concurrency-and-change-tracking.md
│   │   │   │   │   │   │   ├── datacontext-to-dbcontext.md
│   │   │   │   │   │   │   ├── entity-mapping-conversion.md
│   │   │   │   │   │   │   ├── query-translation-gotchas.md
│   │   │   │   │   │   │   ├── relationship-migration.md
│   │   │   │   │   │   │   └── stored-procedure-migration.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── migrating-to-microsoft-data-sqlclient/
│   │   │   │   │       └── SKILL.md
│   │   │   │   ├── desktop/
│   │   │   │   │   └── winforms/
│   │   │   │   │       ├── building-winforms-applications/
│   │   │   │   │       │   ├── ref/
│   │   │   │   │       │   │   ├── async-apis.md
│   │   │   │   │       │   │   ├── dark-mode.md
│   │   │   │   │       │   │   └── detailed-guide.md
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── creating-winforms-custom-controls/
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── managing-winforms-async-apis/
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── managing-winforms-data-binding/
│   │   │   │   │       │   ├── ref/
│   │   │   │   │       │   │   └── detailed-guide.md
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── managing-winforms-designer-code/
│   │   │   │   │       │   ├── ref/
│   │   │   │   │       │   │   └── detailed-guide.md
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── managing-winforms-high-dpi-layout/
│   │   │   │   │       │   ├── ref/
│   │   │   │   │       │   │   └── detailed-guide.md
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       ├── managing-winforms-mvvm/
│   │   │   │   │       │   ├── ref/
│   │   │   │   │       │   │   └── detailed-guide.md
│   │   │   │   │       │   └── SKILL.md
│   │   │   │   │       └── managing-winforms-rendering/
│   │   │   │   │           ├── ref/
│   │   │   │   │           │   └── detailed-guide.md
│   │   │   │   │           └── SKILL.md
│   │   │   │   ├── libraries/
│   │   │   │   │   ├── integrating-autofac-with-dotnet/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-adal-to-msal/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-aspnet-signalr/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-autofac-to-dotnet-di/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-azure-sdk-to-track2/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── authentication.md
│   │   │   │   │   │   │   ├── behavior-audit.md
│   │   │   │   │   │   │   ├── management-plane.md
│   │   │   │   │   │   │   ├── package-catalog.md
│   │   │   │   │   │   │   └── track2-contract.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-bond-interfaces/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-cosmosdb-bulk-executor/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-cryptography-namespaces/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-data-edm-to-odata/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-data-odata-to-odata-core/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-data-services-client/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-documentdb-to-cosmos/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-federated-oidc-token-exchange/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── providers.md
│   │   │   │   │   │   │   └── worked-example.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-newtonsoft-to-system-text-json/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-owin-authentication-handler-to-core/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── core.cs
│   │   │   │   │   │   │   └── map.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-owin-cookie-auth/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-owin-oauth-to-jwt/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   └── entra-validation.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-owin-openid-connect/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-powershell-sdk/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-razorengine-to-razorlight/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-semantic-kernel-to-agents/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   ├── api-mappings.md
│   │   │   │   │   │   │   └── provider-patterns.md
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-spa-services-to-spa-proxy/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-system-spatial/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-to-msmq-messaging/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-webapi-cors/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── migrating-webapi-odata/
│   │   │   │   │       ├── ref/
│   │   │   │   │       │   ├── compatibility-examples.md
│   │   │   │   │       │   └── v4-migration.md
│   │   │   │   │       └── SKILL.md
│   │   │   │   ├── pwsh/
│   │   │   │   │   ├── fixing-windows-only-modules/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── handling-removed-snapins/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-exchange-management-shell/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── migrating-wmi-to-cim/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── powershell-mechanical-fixups/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── replacing-eventlog-with-winevent/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   ├── scanning-powershell-compatibility/
│   │   │   │   │   │   ├── ref/
│   │   │   │   │   │   │   └── custom-rules.md
│   │   │   │   │   │   ├── rules/
│   │   │   │   │   │   │   └── PSCompatibilityRules.psd1
│   │   │   │   │   │   ├── scripts/
│   │   │   │   │   │   │   ├── Get-PSCompatibilityScan.ps1
│   │   │   │   │   │   │   ├── Invoke-PSSACompatibilityScan.ps1
│   │   │   │   │   │   │   └── New-PSSACompatibilityProfile.ps1
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── triaging-powershell-analyzer-findings/
│   │   │   │   │       └── SKILL.md
│   │   │   │   ├── testing/
│   │   │   │   │   ├── generating-upgrade-test-baseline/
│   │   │   │   │   │   └── SKILL.md
│   │   │   │   │   └── managing-dotnet-test-installation/
│   │   │   │   │       └── SKILL.md
│   │   │   │   └── web/
│   │   │   │       ├── aspnet/
│   │   │   │       │   └── migrating-global-asax/
│   │   │   │       │       └── SKILL.md
│   │   │   │       ├── mvc/
│   │   │   │       │   ├── analyzing-cross-host-route-ownership/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   └── pipeline-code.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-aspnet-framework-to-core/
│   │   │   │       │   │   ├── side-by-side.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-aspnet-identity/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-authentication/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   └── membership.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-bundling/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-configuration/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-content-negotiation/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-controllers/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-dependency-injection/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-filters/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   ├── core.cs
│   │   │   │       │   │   │   └── worked-example.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-http-pipeline/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-httpcontext/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-logging/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   └── correlation-ids.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-model-binding/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-razor-views/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   └── view-location-precedence.md
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-routing/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-session-state/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-static-files/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-system-web-adapters/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-mvc-validation/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── migrating-owin-to-aspnet-core/
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   ├── scaffolding-yarp-proxy-project/
│   │   │   │       │   │   ├── ref/
│   │   │   │       │   │   │   ├── auth-setup.md
│   │   │   │       │   │   │   ├── framework-headers.md
│   │   │   │       │   │   │   ├── manual-scaffold.md
│   │   │   │       │   │   │   ├── older-targets.md
│   │   │   │       │   │   │   └── troubleshooting.md
│   │   │   │       │   │   ├── tmpl/
│   │   │   │       │   │   │   ├── auth/
│   │   │   │       │   │   │   │   ├── README.REMOTEAUTH.md
│   │   │   │       │   │   │   │   └── README.SHAREDCOOKIE.md
│   │   │   │       │   │   │   ├── mvc/
│   │   │   │       │   │   │   │   ├── Properties/
│   │   │   │       │   │   │   │   │   └── launchSettings.json
│   │   │   │       │   │   │   │   ├── appsettings.Development.json
│   │   │   │       │   │   │   │   ├── appsettings.json
│   │   │   │       │   │   │   │   ├── Program.cs
│   │   │   │       │   │   │   │   └── ProjectName.csproj
│   │   │   │       │   │   │   └── webapi/
│   │   │   │       │   │   │       ├── Properties/
│   │   │   │       │   │   │       │   └── launchSettings.json
│   │   │   │       │   │   │       ├── appsettings.Development.json
│   │   │   │       │   │   │       ├── appsettings.json
│   │   │   │       │   │   │       ├── Program.cs
│   │   │   │       │   │   │       └── ProjectName.csproj
│   │   │   │       │   │   ├── marker-processor.ps1
│   │   │   │       │   │   ├── scaffold-project.ps1
│   │   │   │       │   │   └── SKILL.md
│   │   │   │       │   └── sharing-authentication-cookies-katana-interop/
│   │   │   │       │       ├── ref/
│   │   │   │       │       │   └── legacy.cs
│   │   │   │       │       └── SKILL.md
│   │   │   │       ├── wcf/
│   │   │   │       │   └── migrating-wcf-to-corewcf/
│   │   │   │       │       └── SKILL.md
│   │   │   │       └── webforms/
│   │   │   │           ├── managing-blazor-server-authentication/
│   │   │   │           │   ├── ref/
│   │   │   │           │   │   ├── cookie-auth-pattern.md
│   │   │   │           │   │   └── endpoint-templates.md
│   │   │   │           │   └── SKILL.md
│   │   │   │           ├── managing-blazor-server-data-access/
│   │   │   │           │   ├── ref/
│   │   │   │           │   │   └── session-state-patterns.md
│   │   │   │           │   └── SKILL.md
│   │   │   │           └── migrating-webforms-to-blazor-server/
│   │   │   │               ├── ref/
│   │   │   │               │   ├── ajax-toolkit.md
│   │   │   │               │   ├── code-transforms.md
│   │   │   │               │   ├── control-reference.md
│   │   │   │               │   └── markup-transforms.md
│   │   │   │               └── SKILL.md
│   │   │   └── scenarios/
│   │   │       ├── aspire-integration/
│   │   │       │   ├── aspire-cli.md
│   │   │       │   ├── assessment.md
│   │   │       │   ├── execution.md
│   │   │       │   └── SKILL.md
│   │   │       ├── aspire-version-upgrade/
│   │   │       │   ├── assessment.md
│   │   │       │   ├── breaking-changes.md
│   │   │       │   ├── execution.md
│   │   │       │   └── SKILL.md
│   │   │       ├── azure-functions-upgrade/
│   │   │       │   └── SKILL.md
│   │   │       ├── azure-migrate/
│   │   │       │   └── SKILL.md
│   │   │       ├── dotnet-arm64-migration/
│   │   │       │   ├── assessment.md
│   │   │       │   ├── execution.md
│   │   │       │   ├── planning.md
│   │   │       │   ├── SKILL.md
│   │   │       │   └── validation.md
│   │   │       ├── dotnet-framework-version-upgrade/
│   │   │       │   ├── assessment.md
│   │   │       │   ├── execution.md
│   │   │       │   ├── planning.md
│   │   │       │   └── SKILL.md
│   │   │       ├── dotnet-version-upgrade/
│   │   │       │   ├── breakdown-hints/
│   │   │       │   │   ├── common.md
│   │   │       │   │   ├── framework-migration.md
│   │   │       │   │   ├── framework-web-migration.md
│   │   │       │   │   └── test.md
│   │   │       │   ├── planning-rules/
│   │   │       │   │   ├── framework-migration.md
│   │   │       │   │   └── modern-upgrade.md
│   │   │       │   ├── strategies/
│   │   │       │   │   ├── all-at-once.md
│   │   │       │   │   ├── bottom-up.md
│   │   │       │   │   └── top-down.md
│   │   │       │   ├── upgrade-options/
│   │   │       │   │   ├── binding-redirects.md
│   │   │       │   │   ├── configuration-migration.md
│   │   │       │   │   ├── cross-app-cookie-auth.md
│   │   │       │   │   ├── dependency-injection.md
│   │   │       │   │   ├── entity-framework.md
│   │   │       │   │   ├── logging-framework.md
│   │   │       │   │   ├── nullable-reference-types.md
│   │   │       │   │   ├── package-management.md
│   │   │       │   │   ├── project-approach.md
│   │   │       │   │   ├── strategy.md
│   │   │       │   │   ├── system-web-adapters.md
│   │   │       │   │   ├── test-coverage.md
│   │   │       │   │   ├── unsupported-api-handling.md
│   │   │       │   │   ├── unsupported-packages.md
│   │   │       │   │   ├── upgrade-options-index.md
│   │   │       │   │   └── windows-native-apis.md
│   │   │       │   ├── assessment.md
│   │   │       │   ├── confirm-options-mcp.md
│   │   │       │   ├── execution.md
│   │   │       │   ├── planning.md
│   │   │       │   ├── post-completion.md
│   │   │       │   └── SKILL.md
│   │   │       ├── newtonsoft-json-migration/
│   │   │       │   └── SKILL.md
│   │   │       ├── nuget-package-upgrade/
│   │   │       │   ├── upgrade-options/
│   │   │       │   │   └── version-reconciliation.md
│   │   │       │   ├── assessment.md
│   │   │       │   ├── execution.md
│   │   │       │   ├── planning.md
│   │   │       │   └── SKILL.md
│   │   │       ├── powershell-51-to-7-upgrade/
│   │   │       │   ├── assessment.md
│   │   │       │   ├── execution.md
│   │   │       │   ├── planning.md
│   │   │       │   ├── SKILL.md
│   │   │       │   └── validation-ladder.md
│   │   │       ├── sdk-style-conversion/
│   │   │       │   └── SKILL.md
│   │   │       ├── semantic-kernel-to-agents-framework/
│   │   │       │   └── SKILL.md
│   │   │       ├── sqlclient-migration/
│   │   │       │   └── SKILL.md
│   │   │       ├── vssdk-sdk-style-conversion/
│   │   │       │   ├── ref/
│   │   │       │   │   └── vssdk-project-format.md
│   │   │       │   └── SKILL.md
│   │   │       ├── webforms-to-blazor-upgrade/
│   │   │       │   └── SKILL.md
│   │   │       └── winforms-feature-adoption/
│   │   │           ├── execution.md
│   │   │           ├── feature-selection.md
│   │   │           ├── planning.md
│   │   │           └── SKILL.md
│   │   └── upgrade-extension.json
│   ├── skills/
│   │   ├── generic/
│   │   │   └── creating-skills/
│   │   │       ├── references/
│   │   │       │   ├── anthropic-best-practices.md
│   │   │       │   ├── quality-checklist.md
│   │   │       │   └── validation-rules.md
│   │   │       ├── scripts/
│   │   │       │   ├── validate_skill.ps1
│   │   │       │   └── validate_skill.sh
│   │   │       ├── templates/
│   │   │       │   └── SKILL-TEMPLATE.md
│   │   │       └── SKILL.md
│   │   └── system/
│   │       ├── dashboard-canvas/
│   │       │   └── SKILL.md
│   │       └── post-scenario-completion/
│   │           └── SKILL.md
│   └── typescript/
│       ├── skills/
│       │   ├── jsts-dependabot/
│       │   │   └── SKILL.md
│       │   ├── jsts-framework-migration/
│       │   │   ├── migrations/
│       │   │   │   └── jasmine-karma-to-vitest.md
│       │   │   └── SKILL.md
│       │   ├── typescript-compiler-upgrade/
│       │   │   ├── 4to5.md
│       │   │   ├── 5to6.md
│       │   │   ├── 6to7.md
│       │   │   ├── compiler-upgrade.md
│       │   │   └── SKILL.md
│       │   ├── typescript-dependencies-upgrade/
│       │   │   ├── react/
│       │   │   │   ├── 17.md
│       │   │   │   ├── 18.md
│       │   │   │   └── 19.md
│       │   │   ├── angular.md
│       │   │   ├── generate-plan.md
│       │   │   ├── i18next.md
│       │   │   ├── karma-jasmine.md
│       │   │   ├── monorepo.md
│       │   │   ├── mui.md
│       │   │   ├── peer-dependencies.md
│       │   │   ├── radix.md
│       │   │   ├── react-hook-form.md
│       │   │   ├── react.md
│       │   │   ├── repair-validation-failures.md
│       │   │   ├── SKILL.md
│       │   │   ├── tanstack.md
│       │   │   └── upgrade-packages.md
│       │   └── typescript-runtime-validation/
│       │       ├── output-contains.md
│       │       ├── per-project-type.md
│       │       ├── plan-authoring.md
│       │       ├── plan-schema.md
│       │       ├── recording.md
│       │       ├── SKILL.md
│       │       ├── standalone-workflow.md
│       │       ├── tests-assertion.md
│       │       └── upgrade-workflow.md
│       └── upgrade-extension.json
├── hooks.json
└── plugin.json
```

## Requirements

- .NET SDK 10.0 or later

## Privacy

### What is sent to GitHub Copilot

This plugin works through GitHub Copilot to analyze and modify code in your
current workspace. To do that, the upgrade agent and its tools include workspace
content in your Copilot requests. Depending on the scenario and the step you are
on, that content can include:

- **Workspace identifiers** — file, project, and solution paths.
- **Source code** — contents and code snippets from the files being analyzed or
  changed, and from project and configuration files such as `.csproj`, `.sln`,
  `package.json`, `Directory.Packages.props`, and `tsconfig.json`.
- **Dependency and framework data** — package names and versions, project
  references, and current and target framework versions.
- **Build and validation output** — restore, build, analyzer, and test results,
  including compiler errors, warnings, diagnostic IDs, and failure messages.
- **Prompts, instructions, and upgrade workspace** — your chat prompts and
  instructions; the generated assessment, `plan.md`, `tasks.md`, and per-task
  files under `tasks/{taskId}/`, including any edits you make to them; and
  preferences and instructions in `scenario-instructions.md`. These files are
  written to your repository under `.github/upgrades/` and persist across
  sessions. The plugin does not independently upload or store them elsewhere,
  but the agent reads them while working and when resuming, so their contents
  may be included in GitHub Copilot requests.

This content is handled as part of your GitHub Copilot requests, subject to the
[GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
For details on how Copilot handles prompts and retention, see the
[GitHub Copilot Trust Center](https://copilot.github.trust.page/).

### Telemetry

The upgrade tools collect usage telemetry: session and persistent device
identifiers, product and environment versions, the selected upgrade scenario,
aggregate workspace metrics, upgrade progress and timing, and diagnostic
identifiers such as error and analysis rule IDs and exception types.

Telemetry does not include source code or file contents. Diagnostics are reduced
to identifiers, counts, and exception types rather than message text. When
collected, repository URL and name telemetry fields are hashed before they are
sent.

Telemetry collection is on by default. To opt out, set the environment variable
`APPMOD_DISABLE_TELEMETRY` to `true` in the environment where you run the plugin.
See the
[Microsoft Privacy Statement](https://privacy.microsoft.com/privacystatement)
for more information.

### Other network activity

The plugin downloads the upgrade tools from nuget.org and npmjs.com, or from the
feeds you have configured.

During .NET analysis and upgrade, the tools query your configured NuGet feeds
(nuget.org by default) for your project's package dependencies, and may download
those packages to inspect them.

## Links

- [Source](https://github.com/microsoft/upgrade-agent-plugins)
