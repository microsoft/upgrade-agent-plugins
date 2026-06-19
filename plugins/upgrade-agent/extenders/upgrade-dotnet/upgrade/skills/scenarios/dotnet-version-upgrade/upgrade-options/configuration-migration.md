# Configuration Migration

**Category**: Modernization

**Applicable when**:
- `app.config` or `web.config` exists in any project, AND
- Any of the following add complexity:
  - Custom configuration section handlers (`IConfigurationSectionHandler`)
  - Config transforms beyond Debug/Release (`Web.Staging.config`, etc.)
  - Encrypted config sections (`<EncryptedData>`)
  - Connection strings with non-standard attributes
  - > 20 `appSettings` keys (high volume warrants review option)

**Not applicable when**:
- No `app.config` or `web.config` in any project
- Already using `appsettings.json` / `IConfiguration`
- Only trivial config (few standard `appSettings` and `connectionStrings`) —
  auto-migration is straightforward, no decision needed, proceed automatically

**Default logic**:
- Recommend **Auto-migrate** if:
  - Standard `appSettings` and `connectionStrings` only
- Recommend **Manual Migration with Mapping Document** if:
  - Custom config section handlers detected, OR
  - Encrypted sections detected, OR
  - Complex transforms beyond Debug/Release, OR
  - > 20 appSettings keys where business meaning of each needs verification

**Options**:
- **Auto-migrate to .NET Core Configuration** *(default when applicable)* —
  automatically converts `app.config`/`web.config` to `appsettings.json` and
  migrates code to `IConfiguration`. Fast, handles standard cases well.
- **Manual Migration with Mapping Document** — generates detailed mapping
  of existing settings before migration. More control for complex configs.

**Stored as**: `Upgrade Options > Modernization > Configuration Migration`

**Affects**: Phase 3 approach in `migrating-aspnet-framework-to-core` skill, whether a
config review task is added to the plan.
