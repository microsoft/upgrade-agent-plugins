# Breakdown Hints — .NET Framework Migration

Hints for tasks involving .NET Framework → modern .NET migration.
Load this file when the task scope includes projects migrating from .NET Framework.

---

### hint: system-web-dependency
**Applies to task types**: TFM upgrade, multi-targeting, project migration
**Condition**: A non-web project has System.Web references
**Detection**:
- Project references System.Web assembly
- Code uses `HttpContext.Current`, `HttpRequest`, `HttpResponse` from System.Web
- Project is NOT a web project (it's a class library, console app, or service consumed by a web project)
**Recommendation**: Projects with System.Web dependencies cannot be multi-targeted
in the traditional way. The System.Web API surface must be replaced with
abstractions injectable via DI before the project can support .NET Core.
Break this work from other TFM updates — it requires different expertise
and has different risk profile.
**Priority**: SHOULD

---

### hint: windows-api-isolation
**Applies to task types**: TFM upgrade, multi-targeting, API migration
**Condition**: Project uses Windows-specific APIs that are not available on all platforms
**Detection**:
- Code: `DllImport`, `RegistryKey`, `Registry`, `System.Drawing` (non-Common),
  `System.Windows.Forms`
- Packages: Windows-only packages without cross-platform equivalents
- P/Invoke declarations targeting Windows DLLs
**Recommendation**: Windows API compatibility is a distinct concern from general
TFM upgrade. If the project has both general API changes and Windows-specific
API changes, break them apart — general changes first, Windows compatibility
second (may require Windows Compatibility Pack decision).
**Priority**: SHOULD
