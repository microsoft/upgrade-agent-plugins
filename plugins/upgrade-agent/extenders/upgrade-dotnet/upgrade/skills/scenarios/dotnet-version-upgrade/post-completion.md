# Post-Completion Suggestions — .NET Version Upgrade

This file defines **scenario-specific next-step candidates** for the .NET version upgrade scenario. The `post-scenario-completion` system skill controls the overall format and generic actions (generate report, discover more opportunities) — do NOT duplicate those here.

Each suggestion below has an **applicability check** you MUST perform. Only include suggestions whose conditions are met. If none apply, return nothing — the system skill handles the generic items.

**Prefer signals over file scanning.** When `detectedSignals` is available in the `complete_task` response, use those to evaluate applicability. Only fall back to reading project files or assessment.md when no matching signal exists. Never mention signals or their absence to the user — this is an internal optimization.

---

## Candidate 1: Add Aspire (emoji: 🚀)

**Signal-based check:** If signals do NOT include `HasAspire`, Aspire is not present — suggest adding it.
**Fallback check (no signals):** Look at the upgraded project files for `Aspire.Hosting` or `Aspire.AppHost` package references.

**If Aspire is NOT present:**
- **Title:** Add Aspire for better development experience
- **Description:** Your solution doesn't use Aspire yet. Aspire can improve your inner-loop development experience with a unified dashboard for logs, traces, and metrics across all services — and it also provides an optional deployment story to Azure Container Apps or AKS.
- **CTA:** Would you like me to integrate Aspire into your solution?

**If Aspire IS present — check the version:**
Read the `Aspire.Hosting` or `Aspire.AppHost` package version and compare to the latest stable (currently 9.x). If the version is older:
- **Title:** Upgrade Aspire to the latest version
- **Description:** Your solution uses Aspire {current version}. A newer version is available — upgrading Aspire will give you the latest dashboard improvements and component APIs.
- **CTA:** Would you like me to upgrade Aspire to the latest version?

If the version is already current, skip Aspire entirely.

## Candidate 2: Migrate to EF Core (emoji: 🗄️)

**Signal-based check:** If signals include `HasEntityFramework` AND do NOT include `HasEfCore`, suggest EF Core migration. If `HasEfCore` is present, the migration has already happened — skip. If neither `HasEntityFramework` nor `HasEfCore` is in signals, the project doesn't use EF — skip.
**Fallback check (no signals):**

1. Read `assessment.md` and check whether Entity Framework 6 was detected in the solution. If EF6 was not listed, skip this suggestion entirely — the project doesn't use EF6.

2. If EF6 was detected, check whether EF Core is already present. Look for `Microsoft.EntityFrameworkCore` package references in the affected project files (or in `assessment.md` if it lists current packages). If EF Core is already present, the migration has already happened — skip.

**If EF6 was detected AND EF Core is not present:**
- **Title:** Migrate from Entity Framework 6 to EF Core
- **Description:** Your projects still use Entity Framework 6. Now that the .NET upgrade is complete, migrating to EF Core is a natural next step — it gives you better performance, LINQ improvements, and first-class support for modern .NET features.
- **CTA:** Would you like me to start the EF Core migration?

---

## Candidate 3: Adopt Modern WinForms Features (emoji: 🎨)

**Signal-based check:** If signals include `HasWinForms` AND target TFM is >= net9.0, WinForms projects can use modern features.
**Fallback check (no signals):** Look for `<UseWindowsForms>true</UseWindowsForms>` in upgraded project files AND verify target framework is net9.0 or higher.

**If WinForms detected AND upgraded to .NET 9+:**
- **Title:** Adopt modern WinForms features (dark mode, async APIs, MVVM)
- **Description:** Your WinForms projects are now on .NET 9+, which unlocks dark mode support, modern async APIs with cancellation token support, and improved data binding for MVVM patterns. These features can enhance your desktop applications with better user experience and code quality.
- **CTA:** Would you like me to modernize your WinForms UI code with these features?

**If WinForms detected AND upgraded to .NET 8:**
- **Title:** Adopt MVVM pattern for better testability
- **Description:** Your WinForms projects are now on .NET 8+, which includes improved data binding support. You can adopt the MVVM pattern to separate business logic from UI, making your application more testable and maintainable.
- **CTA:** Would you like me to refactor your WinForms code to use MVVM?

If WinForms is not detected or TFM is below .NET 8, skip this suggestion.

---

## What NOT to suggest

Do not suggest other signals from `assessment.md` (Newtonsoft.Json, WCF, ADO.NET, OWIN, etc.) — these should have been addressed during the upgrade tasks. Only suggest Aspire, EF6, and WinForms as described above.
