# Upgrade Option: Version Reconciliation (Divergent Versions)

**When this applies**: The assessment reported a **Divergent** result (`Pkg.0003`) — the scoped
projects need or support different versions of the same package — or a user-provided version is
incompatible with one or more projects' target frameworks.

Pick one option per package. Confirm with the user when the trade-off is material (excluding a
project, changing a target framework).

## Options

### A. Highest common compatible version (default)
Use the newest version that is compatible with **every** scoped project's target framework.
- **Pros**: one version everywhere; simplest to maintain; CPM-friendly.
- **Cons**: may be older than the latest available, so some projects don't get the newest features.
- **Use when**: a common compatible version exists and is acceptable to the user.

### B. Upgrade the lagging project's target framework first
A project supports only an older package version because its TFM is too old. Upgrade that project's
target framework first (consider the `dotnet-version-upgrade` scenario), then apply the unified
package version.
- **Pros**: unblocks a single up-to-date version for all projects.
- **Cons**: a TFM upgrade is a larger change with its own risks.
- **Use when**: one or two projects hold everyone back and a TFM bump is in scope.

### C. Per-project versions (pin / CPM `VersionOverride`)
Let different projects use different versions: pin per project, or under CPM use `VersionOverride`
on the projects that need a different version from the central one.
- **Pros**: each project gets the newest version it supports; no TFM change required.
- **Cons**: multiple versions in the repo; potential diamond-dependency conflicts at runtime.
- **Use when**: a single version is not feasible and the projects don't share a runtime boundary
  that requires identical versions. Apply via the **managing-package-references** skill.

### D. Exclude the incompatible project
Upgrade the compatible projects and leave the incompatible project on its current version.
- **Pros**: unblocks the majority immediately.
- **Cons**: the excluded project is left behind; document why.
- **Use when**: one project can't be upgraded now and doesn't need to match the others.

## After choosing

Record the chosen option (and any excluded projects or per-project versions) in
`scenario-instructions.md` so execution applies it consistently.
