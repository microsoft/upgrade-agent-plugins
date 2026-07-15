# Changelog

All notable changes to the upgrade-agent plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Baseline 1.1.202 - 2026-07-15

This is the initial published baseline. It enumerates the skills and scenarios
shipping in this version; subsequent releases list changes relative to this baseline.

### Existing Skills

#### Cloud

- migrating-azure-functions-startup — Migrates Azure Functions projects from in-process Startup hooks (FunctionsStartup, IFunctionsHostBuilder) to the isolated worker model with Program.cs service registration.
- migrating-azure-functions-to-v2 — Migrates Azure Functions projects from legacy HostBuilder or in-process model to the modern Version 2.x pattern using IHostApplicationBuilder and Application Insights.

#### Common

- building-projects — Build tool selection and orchestration for .NET projects during modernization upgrades.
- converting-to-cpm — Converts .NET projects and solutions to NuGet Central Package Management (CPM) with Directory.Packages.props.
- converting-to-sdk-style — Converts legacy non-SDK-style .NET project files (.csproj, .vbproj, .fsproj) to modern SDK-style format while preserving target frameworks, dependencies, and build behavior.
- managing-legacy-dotnet-packages — Manages NuGet packages in old-style .NET Framework projects (.NET Framework 4.x).
- managing-package-references — Manages .NET package references and dependencies in project files.
- managing-target-frameworks — Manages target frameworks in .NET project files (.csproj, .vbproj, .fsproj).
- migrating-csharp-nullable-references — Enable nullable reference types in a C# project and systematically resolve all warnings.
- modernizing-csharp-version — Upgrade C# code to use newer C# language features.
- modifying-project-properties — Modifies .NET project properties in PropertyGroup elements within .csproj, .vbproj, and Directory.Build.props files.

#### Data

- migrating-edmx-to-code-first — Migrates Entity Framework 6 EDMX-based models (Database-First/Model-First) to EF Core Code-First.
- migrating-ef-dbcontext — Migrates Entity Framework DbContext registration from Global.asax/Startup to ASP.NET Core dependency injection in Program.cs.
- migrating-ef6-code-first-to-ef-core — Migrates Entity Framework 6 Code-First projects to EF Core.
- migrating-linq-to-sql-to-ef-core — Migrates LINQ to SQL (System.Data.Linq) data access layer to Entity Framework Core during .NET Framework to modern .NET upgrades.
- migrating-to-microsoft-data-sqlclient — Migrates .NET projects from System.Data.SqlClient to Microsoft.Data.SqlClient, handling package references, namespace updates, connection string encryption changes, and behavioral differences.

#### Desktop › WinForms

- building-winforms-applications — Structures WinForms applications with Designer-compatible patterns, proper code organization, and build/runtime compatibility.
- creating-winforms-custom-controls — Creates custom controls and UserControls for modern WinForms (.NET 6+).
- managing-winforms-async-apis — Adopts modern WinForms async APIs (.NET 9/10) including Control.InvokeAsync, Form.ShowAsync/ShowDialogAsync, and TaskDialog.ShowDialogAsync.
- managing-winforms-data-binding — Implements WinForms data binding patterns with BindingSource, INotifyPropertyChanged, validation, and master-detail scenarios.
- managing-winforms-designer-code — Governs WinForms Designer-generated code structure and InitializeComponent patterns.
- managing-winforms-high-dpi-layout — Implements WinForms high-DPI fluent layouts using TableLayoutPanel, FlowLayoutPanel, and DPI-aware design patterns.
- managing-winforms-mvvm — Implements MVVM pattern in WinForms applications (.NET 8+) with ViewModels, Commands, and DataContext.
- managing-winforms-rendering — Implements custom painting and rendering in WinForms using GDI and GDI+.

#### Libraries

- integrating-autofac-with-dotnet — Migrates Autofac dependency injection configuration from ASP.NET Framework to ASP.NET Core's hosting model while keeping Autofac as the DI container.
- migrating-adal-to-msal — Migrates deprecated ADAL (Microsoft.IdentityModel.Clients.ActiveDirectory) to MSAL (Microsoft.Identity.Client) for Azure AD authentication.
- migrating-aspnet-signalr — Migrates the obsolete ASP.NET SignalR (Microsoft.AspNet.SignalR) to ASP.NET Core SignalR (Microsoft.AspNetCore.SignalR) for real-time communication.
- migrating-autofac-to-dotnet-di — Removes Autofac entirely and migrates to ASP.NET Core built-in DI by mapping container registrations, lifetimes, and module patterns.
- migrating-azure-keyvault — Migrates from the deprecated Microsoft.Azure.KeyVault SDK to the modern Azure.Security.KeyVault client libraries (Secrets, Keys, Certificates).
- migrating-azure-servicebus — Migrates the deprecated WindowsAzure.ServiceBus to Azure.Messaging.ServiceBus for Azure Service Bus messaging.
- migrating-azure-storage — Migrates the deprecated WindowsAzure.Storage to the modern Azure SDK storage libraries (Azure.Storage.Blobs, Azure.Storage.Queues, Azure.Storage.Files.Shares, Azure.Data.Tables).
- migrating-bond-interfaces — Migrates from the obsolete Microsoft.Bond.Interfaces package to the unified Bond.CSharp SDK for Bond serialization.
- migrating-cosmosdb-bulk-executor — Migrates from the deprecated Microsoft.Azure.CosmosDB.BulkExecutor library to the built-in bulk execution support in Microsoft.Azure.Cosmos SDK.
- migrating-cryptography-namespaces — Migrates System.Security.Cryptography namespace usage from .NET Framework to modern .NET.
- migrating-data-edm-to-odata — Migrates the obsolete Microsoft.Data.Edm (OData v1–v3 EDM types) to Microsoft.OData.Edm for OData v4.
- migrating-data-odata-to-odata-core — Migrates the obsolete Microsoft.Data.OData (OData v1–v3) to Microsoft.OData.Core for OData v4 serialization.
- migrating-data-services-client — Migrates the obsolete Microsoft.Data.Services.Client (WCF Data Services) to Microsoft.OData.Client for OData v4 client access.
- migrating-documentdb-to-cosmos — Migrates from the deprecated Microsoft.Azure.DocumentDB SDK (V2) to the modern Microsoft.Azure.Cosmos SDK (V3) for Azure Cosmos DB.
- migrating-newtonsoft-to-system-text-json — Migrates .NET projects from Newtonsoft.Json to System.Text.Json, updating package references, code files, and handling API differences.
- migrating-owin-cookie-auth — Migrates legacy OWIN cookie authentication (Microsoft.Owin.Security.Cookies) to ASP.NET Core cookie authentication (Microsoft.AspNetCore.Authentication.Cookies).
- migrating-owin-oauth-to-jwt — Migrates legacy OWIN OAuth bearer authentication (Microsoft.Owin.Security.OAuth) to ASP.NET Core JWT Bearer authentication (Microsoft.AspNetCore.Authentication.JwtBearer).
- migrating-owin-openid-connect — Migrates legacy OWIN OpenID Connect authentication (Microsoft.Owin.Security.OpenIdConnect) to ASP.NET Core OpenID Connect (Microsoft.AspNetCore.Authentication.OpenIdConnect).
- migrating-powershell-sdk — Migrates the legacy System.Management.Automation (PowerShell SDK) references from obsolete .NET Framework (Windows PowerShell 5.1) to modern .NET (PowerShell 7+).
- migrating-razorengine-to-razorlight — Migrates the deprecated RazorEngine to RazorLight for Razor template rendering outside of MVC.
- migrating-semantic-kernel-to-agents — Migrates .NET projects from Microsoft Semantic Kernel Agents (Microsoft.SemanticKernel.Agents) to Microsoft Agent Framework (Microsoft.Agents.AI).
- migrating-spa-services-to-spa-proxy — Migrates ASP.NET Core projects from the obsolete Microsoft.AspNetCore.SpaServices.Extensions to Microsoft.AspNetCore.SpaProxy for Angular and React SPAs.
- migrating-system-spatial — Migrates the obsolete System.Spatial (OData v1–v3 spatial types) to Microsoft.Spatial for OData v4.
- migrating-to-msmq-messaging — Migrates .NET projects from System.Messaging to MSMQ.Messaging for .NET Core compatibility.
- migrating-webapi-cors — Migrates legacy ASP.NET Web API CORS (Microsoft.AspNet.WebApi.Cors) to ASP.NET Core CORS (Microsoft.AspNetCore.Cors).
- migrating-webapi-odata — Migrates legacy ASP.NET Web API OData (Microsoft.AspNet.WebApi.OData) to ASP.NET Core OData (Microsoft.AspNetCore.OData).

#### Testing

- generating-upgrade-test-baseline — Generates behavior-locking tests before a .NET upgrade using the external dotnet-test plugin.
- managing-dotnet-test-installation — Installs the external dotnet-test plugin when its test-generation agent is unavailable.

#### Web › ASP.NET

- migrating-global-asax — Migrates Global.asax application lifecycle events to ASP.NET Core middleware, startup configuration, and Program.cs.

#### Web › MVC

- migrating-aspnet-framework-to-core — Orchestrates migration of ASP.NET Framework (System.Web) MVC and WebAPI projects to ASP.NET Core.
- migrating-aspnet-identity — Migrates ASP.NET MVC Identity to ASP.NET Core Identity, updating IdentityDbContext, UserManager, SignInManager, authentication middleware, and OWIN cleanup.
- migrating-mvc-authentication — Migrates ASP.NET MVC and Web API authentication and authorization to ASP.NET Core, covering Forms Authentication, Membership providers, Windows Authentication, token-based auth, authorization rules, and anti-forgery tokens.
- migrating-mvc-bundling — Migrates ASP.NET MVC bundling and minification from System.Web.Optimization to direct script/link tags in ASP.NET Core Razor views.
- migrating-mvc-configuration — Migrates ASP.NET Framework Web.config configuration to ASP.NET Core appsettings.json and IConfiguration/IOptions patterns.
- migrating-mvc-content-negotiation — Migrates ASP.NET Web API content negotiation and formatters to ASP.NET Core equivalents.
- migrating-mvc-controllers — Migrates ASP.NET Framework controllers and action results to ASP.NET Core equivalents, covering both MVC (Controller) and WebAPI (ApiController) patterns.
- migrating-mvc-dependency-injection — Migrates dependency injection configuration from ASP.NET Framework MVC and WebAPI projects to ASP.NET Core built-in DI or modernized third-party container integration.
- migrating-mvc-filters — Migrates ASP.NET MVC global filters (GlobalFilterCollection, HandleErrorAttribute, FilterConfig) to ASP.NET Core exception handling middleware and filter pipeline.
- migrating-mvc-http-pipeline — Migrates ASP.NET Framework HttpModules, HttpHandlers, and Global.asax events to ASP.NET Core middleware and endpoints.
- migrating-mvc-httpcontext — Migrates ASP.NET Framework HttpContext, Request, and Response usage to ASP.NET Core equivalents.
- migrating-mvc-logging — Migrates ASP.NET Framework logging and diagnostics to ASP.NET Core built-in logging abstractions, error handling middleware, and health checks.
- migrating-mvc-model-binding — Migrates ASP.NET Framework model binding to ASP.NET Core, including binding source attributes, custom model binders, value providers, and over-posting protection.
- migrating-mvc-razor-views — Migrates ASP.NET MVC Razor views to ASP.NET Core by converting HtmlHelpers to TagHelpers, child actions to ViewComponents, and updating layout infrastructure.
- migrating-mvc-routing — Converts ASP.NET MVC RouteCollection-based routing to ASP.NET Core endpoint routing with MapControllerRoute in Program.cs.
- migrating-mvc-session-state — Migrates ASP.NET Framework session state, TempData, and application state to ASP.NET Core equivalents.
- migrating-mvc-static-files — Migrates ASP.NET MVC static file serving and virtual path providers to ASP.NET Core conventions.
- migrating-mvc-system-web-adapters — Provides System.Web Adapters overlay guidance for incremental ASP.NET Framework to ASP.NET Core migration.
- migrating-mvc-validation — Migrates ASP.NET Framework validation to ASP.NET Core including data annotations, custom ValidationAttribute classes, ModelState handling, client-side unobtrusive validation, and FluentValidation integration.
- migrating-owin-to-aspnet-core — Migrates OWIN/Katana middleware, authentication, pipeline components, and SignalR 2.x to native ASP.NET Core equivalents.
- scaffolding-yarp-proxy-project — Scaffolds a new ASP.NET Core project with YARP reverse proxy alongside an existing .NET Framework MVC or WebAPI project for incremental side-by-side migration.

#### Web › WCF

- migrating-wcf-to-corewcf — Migrates server-side WCF services from .NET Framework to CoreWCF for .NET 6+.

#### Web › Web Forms

- managing-blazor-server-authentication — Manages authentication in Blazor Server applications with ASP.NET Core Identity.
- managing-blazor-server-data-access — Manages data access and state in Blazor Server applications.
- migrating-webforms-to-blazor-server — Migrates ASP.NET Web Forms applications to Blazor Server using Blazor patterns.

### Existing Scenarios

- .NET Framework Version Upgrade — Upgrade .NET Framework projects to .NET Framework 4.8.1 (net481), staying on full .NET Framework without migrating to modern .NET (net8.0+).
- .NET Version Upgrade — Upgrade .NET projects to newer .NET versions, including guidance on current release status, support lifecycle (LTS/STS), and recommended upgrade targets.
- Aspire Integration — Adds Aspire orchestration to an existing repository for inner-loop development and optional Azure deployment readiness.
- Aspire Version Upgrade — Upgrade existing Aspire projects to a newer Aspire version.
- Azure Functions Upgrade — Upgrade Azure Functions project from in-process model to isolated worker model.
- Azure Migrate — Migrates applications to Azure cloud services by starting an app modernization migration session.
- Newtonsoft.Json Migration — Migrates .NET projects from Newtonsoft.Json to System.Text.Json.
- NuGet Package Upgrade — Upgrade one or more NuGet packages from their current version to a target version across a project, several projects, a folder, a solution, or the whole repository.
- SDK-Style Conversion — Converts legacy .NET projects to SDK-style project format.
- Semantic Kernel to Agents Framework — Migrates .NET projects from Semantic Kernel to the Microsoft Agents Framework.
- SqlClient Migration — Migrates .NET projects from System.Data.SqlClient to Microsoft.Data.SqlClient.
- Web Forms to Blazor Upgrade — Upgrade ASP.NET Web Forms projects to modern .NET.
- WinForms Feature Adoption — Adopts modern WinForms features in .NET 8+ applications including dark mode (Application.SetColorMode, SystemColors), async APIs (Control.InvokeAsync, Form.ShowDialogAsync, TaskDialog.ShowDialogAsync), and MVVM patterns (ViewModels, INotifyPropertyChanged, Commands, DataContext).
