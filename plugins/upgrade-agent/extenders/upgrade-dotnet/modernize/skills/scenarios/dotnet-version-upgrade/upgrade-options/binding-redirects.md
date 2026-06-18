# Assembly Binding Redirects

**Category**: Modernization

**Applicable when**:
- `<assemblyBinding>` / `<dependentAssembly>` entries found in
  `app.config` or `web.config` of any project

**Not applicable when**:
- No binding redirects found in any config file
- Solution already uses SDK-style projects exclusively (redirects auto-managed,
  not hand-authored)

**Default logic**:
- Recommend **Remove** if:
  - Redirects appear auto-generated (Visual Studio boilerplate patterns), OR
  - No underlying version conflicts between packages
- Recommend **Document and Review** if:
  - Hand-authored redirects detected (non-standard formatting or comments), OR
  - Redirects span major version jumps (e.g., binding 1.x to 4.x — indicates
    real conflicts that may resurface), OR
  - > 10 redirects present (volume warrants review before bulk removal)

**Options**:
- **Remove Binding Redirects** *(default when applicable)* — removes all redirects.
  .NET Core handles assembly resolution differently and does not need them.
- **Document and Review Before Removing** — generates report of all redirects
  and their purposes before removal. Use when redirects may indicate real
  underlying version conflicts.

**Stored as**: `Upgrade Options > Modernization > Assembly Binding Redirects`

**Affects**: Whether a review task is added to the plan, or redirects are
handled inline during project file cleanup tasks.
