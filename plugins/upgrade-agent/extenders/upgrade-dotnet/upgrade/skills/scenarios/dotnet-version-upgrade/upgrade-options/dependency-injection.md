# Dependency Injection

**Category**: Modernization

**Applicable when**:
- A third-party IoC container is in use:
  - Autofac
  - Unity / Microsoft.Unity
  - Ninject
  - Castle Windsor
  - StructureMap
  - Simple Injector
- OR: custom `IDependencyResolver` (MVC) or `IHttpControllerActivator` (WebAPI) detected

**Not applicable when**:
- No DI container detected (using `new`, service locator, or static factories)
- Already using `Microsoft.Extensions.DependencyInjection`
- Container is only used for a small number of registrations with no
  container-specific features (decorators, named registrations, modules, etc.)

**Default logic**:
- Recommend **Migrate to Built-in DI** by default — .NET Core's built-in DI is
  the standard, and most containers can be replaced without major effort. Migrating
  removes a dependency and aligns with the framework's native patterns.
- Recommend **Keep Existing** only if:
  - Heavy use of container-specific features detected that have no built-in equivalent:
    - Autofac modules (`IModule` implementations)
    - Named/keyed registrations (note: .NET 8+ supports keyed services natively)
    - Decorators
    - Property injection across many types
    - Child/nested lifetime scopes
  - AND team has explicitly confirmed significant container investment

**Options**:
- **Migrate to Built-in DI Container** *(default when applicable)* — migrates to
  `Microsoft.Extensions.DependencyInjection`. Standard for .NET Core. Seamless
  framework integration.
- **Keep Existing IoC Container** — retains current container with adapter package
  for .NET Core integration. Preserves container-specific features.

**Stored as**: `Upgrade Options > Modernization > Dependency Injection`

**Affects**: Phase 4 approach in `migrating-aspnet-framework-to-core` skill, which
`aspnet-di-migration` satellite mode is used during execution.
