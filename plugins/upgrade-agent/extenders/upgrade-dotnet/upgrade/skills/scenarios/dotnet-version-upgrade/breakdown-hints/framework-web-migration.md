# Breakdown Hints — Web (ASP.NET Framework)

Hints for tasks that involve ASP.NET Framework web projects (System.Web, MVC, WebAPI).
Load this file when the task scope includes web projects being migrated.

**Tool tip**: Use `get_code_dependencies(projectPath, filePath)` on individual
controllers or views to get their full dependency graph before deciding how
to break down migration work.

---

### hint: web-controller-migration-units
**Applies to task types**: web layer migration, controller migration
**Condition**: Web project has controllers that need migrating to ASP.NET Core
**Detection**:
- Task scope includes migrating controllers from old web project to new Core project
- Multiple controllers exist in the project
**Recommendation**: Each controller is its own subtask — no grouping.
1. Triage controllers by reading each file — note constructor parameter count,
   [Authorize] attributes, action count. Group by feature folder/area/naming.
   Order: simplest first, auth-dependent last.
2. When executing each subtask, use `get_code_dependencies` on the controller
   to discover its full dependency tree (services, models, views, packages)
   before making changes.
**Priority**: SHOULD (MUST if >5 controllers)

---

### hint: web-di-container-migration
**Applies to task types**: web layer migration, dependency injection migration
**Condition**: Web project uses a third-party DI container
**Detection**:
- Packages: Autofac, Ninject, StructureMap, Unity, SimpleInjector, Castle.Windsor, DryIoc
- Code patterns: `ContainerBuilder`, `IKernel`, `IContainer`, `IUnityContainer`
- Global.asax or Startup.cs has container configuration
**Recommendation**: DI container migration is a cross-cutting concern that touches
every service registration. Break separately from controller/view migration:
1. Map all registrations from old container to MS DI equivalents
2. Identify registrations using container-specific features
   (decorators, interceptors, child containers, modules)
3. Migrate registrations
4. Verify all services resolve correctly
**Priority**: SHOULD (MUST if >20 registrations or uses advanced features)

---

### hint: web-auth-migration-isolation
**Applies to task types**: web layer migration, auth migration
**Condition**: Web project uses ASP.NET Identity, OWIN auth, Forms Authentication,
or custom auth middleware
**Detection**:
- Packages: Microsoft.AspNet.Identity.*, Microsoft.Owin.Security.*, Owin, Microsoft.Owin
- Files: Startup.Auth.cs, IdentityConfig.cs, ApplicationUserManager
- Web.config sections: `<authentication>`, `<authorization>`, `<membership>`, `<roleManager>`
**Recommendation**: Auth migration is high-risk and should be isolated. Never
combine with controller/view migration:
1. Scaffold Core Identity with equivalent user/role model
2. Migrate user store and data (if applicable)
3. Configure auth middleware pipeline
4. Migrate auth-dependent controllers
5. Verify login/logout/role-check flows
**Priority**: MUST

---

### hint: web-config-to-appsettings
**Applies to task types**: web layer migration, configuration migration
**Condition**: Web project uses Web.config for app settings, connection strings,
or custom config sections
**Detection**:
- Web.config contains `<appSettings>`, `<connectionStrings>`, or custom `<configSections>`
- Code: `ConfigurationManager.AppSettings`, `ConfigurationManager.ConnectionStrings`,
  `WebConfigurationManager`, custom `ConfigurationSection` classes
**Recommendation**: Configuration migration should happen early since many other
components depend on it. Break separately if:
- Custom config sections exist (need `IOptions<T>` pattern design)
- Config values are used in DI registrations
- Environment-specific transforms exist (Web.Debug.config, Web.Release.config)
**Priority**: SHOULD

---

### hint: web-bundling-and-static-assets
**Applies to task types**: web layer migration, view migration
**Condition**: Web project uses System.Web.Optimization bundling or custom asset pipeline
**Detection**:
- Packages: Microsoft.AspNet.Web.Optimization, BundleTransformer.*
- Files: BundleConfig.cs, App_Start/BundleConfig.cs
- View references: `@Scripts.Render`, `@Styles.Render`
- No wwwroot folder (assets in Content/, Scripts/ folders)
**Recommendation**: Static asset pipeline is distinct from Razor view migration.
Break separately:
1. Set up wwwroot structure and copy static files
2. Configure static file middleware
3. Replace bundling references in views
**Priority**: SHOULD

---

### hint: web-middleware-pipeline
**Applies to task types**: web layer migration
**Condition**: Web project uses OWIN middleware or HTTP modules/handlers
**Detection**:
- OWIN: Startup.cs with `IAppBuilder`, `app.Use*` patterns
- HTTP Modules: `<httpModules>` or `<modules>` in Web.config,
  classes implementing `IHttpModule`
- HTTP Handlers: `<httpHandlers>` or `<handlers>` in Web.config,
  classes implementing `IHttpHandler`, `.ashx` files
**Recommendation**: Middleware pipeline should be set up before migrating
controllers, since controllers depend on middleware being correctly configured.
Map each OWIN middleware or HTTP module to its ASP.NET Core equivalent.
**Priority**: SHOULD

---

### hint: system-messaging-replacement
**Applies to task types**: web layer migration, service migration
**Condition**: Project uses System.Messaging (MSMQ)
**Detection**:
- References: System.Messaging
- Code: `MessageQueue`, `Message`, `MessageQueueTransaction`
- Config: MSMQ queue names in config
**Recommendation**: System.Messaging is Windows-only with no direct .NET Core
equivalent. Requires a technology decision (RabbitMQ, Azure Service Bus, etc.)
and should be isolated as a separate concern with its own subtask.
**Priority**: MUST

---

### hint: ef6-initialization-for-core
**Applies to task types**: data access migration, web layer migration
**Condition**: Project uses Entity Framework 6.x with database initializers or migrations
**Detection**:
- Packages: EntityFramework (6.x)
- Code: `Database.SetInitializer`, `DbMigrationsConfiguration`,
  `IDatabaseInitializer`, `CreateDatabaseIfNotExists`, `MigrateDatabaseToLatestVersion`
- Config: `<entityFramework>` section in app.config/web.config
**Recommendation**: EF6 can run on .NET Core but initialization patterns differ.
The `<entityFramework>` config section doesn't work — initialization must move
to code. Break from general web migration and handle separately.
**Priority**: SHOULD
