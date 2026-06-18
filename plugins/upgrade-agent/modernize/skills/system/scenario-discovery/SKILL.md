---
name: scenario-discovery
description: Discover and present potential modernization (upgrade) opportunities for a solution or set of projects
metadata:
  discovery: system
---

# Scenario Discovery

Scan the user's solution for modernization opportunities and present them clearly.

## When to use

- User asks "what can I modernize?", "scan my repo", "find upgrade opportunities", or similar exploratory requests
- Post-completion "Discover more opportunities" flow
- Any time you need to analyze a solution before the user has picked a specific scenario

## Step 1 — Run discovery

Call `discover_upgrade_scenarios(solutionPath, projectPath)` to analyze the solution.

- Use the solution path from the workspace or from what the user provided.
- If the user mentioned a specific project, pass it as `projectPath`. Otherwise, pass it empty to scan the entire solution.

**If the tool returns no results:** tell the user no modernization opportunities were found for their solution and ask if they'd like to try with a different solution or project scope.

## Step 2 — Present results

Use the tool result and follow the format below.

## Rules

1. **Never mention implementation details** — do not say "signals", "analysis rules", "ISliceNodeProvider", "rule instances", or any internal mechanism. The user sees *what* was found, not *how* it was detected.
2. **Never show scenario IDs** — use the scenario name/description only.
3. **Never invent scenarios** — only present scenarios that appear in the tool result.
4. **Value proposition first** — lead with *why* this matters to the user, not *what* was detected.
5. **Group by priority** — scenarios are already sorted by importance/weight. Present them in the order given.

## Presentation format

### Header

```
🔍 **Found {N} modernization opportunity/opportunities**
```

### Scenario cards — show top 5 max

Present **at most 5** scenarios, sorted by priority (they're already sorted in the tool result). Each scenario is a block separated by `---`:

```
{emoji} **{Scenario name}**
{Value proposition — 1-2 sentences explaining why this upgrade is valuable.}

Affects: {up to 3 project names}
```

**Project names:**
- The tool returns full project paths. Extract just the project name (file name without extension) for the summary display.
- Show at most 3 names. If more: `Affects: WebApp, DataLayer, Common, and 4 more`
- The full discovery report (if requested) should use full paths.

**Emoji selection:**
- 🚀 Version upgrades (.NET, framework)
- 🗄️ Database/data access (EF, SQL, LINQ to SQL)
- 🔄 API migrations (WCF, Newtonsoft, SqlClient)
- 🤖 AI/ML framework migrations (Semantic Kernel)
- ☁️ Cloud integrations (Aspire, Azure Functions)
- 🔒 Security (vulnerable packages)
- 📦 Project modernization (SDK-style conversion)

### Footer

**If more than 5 scenarios exist**, add after the last card:

```
...and {M} more opportunities. Would you like me to generate a full discovery report with all of them?
```

**Call to action (always, after cards or overflow note):**

- **1 scenario:** `Would you like me to start this upgrade?`
- **2-5 scenarios:** `Which would you like to start with? I recommend **{first}** — {one-sentence reason}.`
- **6+ scenarios:** `Which would you like to start with? I recommend **{first}** as the highest-priority item.`

## Example output

> 🔍 **Found 3 modernization opportunities**
>
> ---
>
> 🚀 **Upgrade to .NET 10**
> Move your projects to .NET 10 for better performance, new language features, and long-term support.
>
> Affects: WebApp, DataLayer, Common, and 2 more
>
> ---
>
> 🔄 **Migrate Newtonsoft.Json to System.Text.Json**
> System.Text.Json offers better performance and is the built-in JSON library in modern .NET.
>
> Affects: WebApp, DataLayer
>
> ---
>
> 🔒 **Fix vulnerable NuGet packages**
> Some packages have known security vulnerabilities that should be addressed.
>
> Affects: WebApp
>
> ---
>
> Which would you like to start with? I recommend **Upgrade to .NET 10** — it's the highest-impact change and other migrations benefit from the latest framework.

## Full discovery report

When the user asks for the full report (only relevant when 6+ scenarios were found and the summary was truncated), produce a markdown document using ALL data from the tool result — no truncation.

⛔ **Follow this template exactly.** Do NOT add sections, recommendations, lifecycle references, or any content beyond what the tool returned. The report presents what was *found* — not what you *think* might be useful. Unverified recommendations (e.g., "enable nullable", "add Aspire") make the report unreliable. If additional analysis is wanted, that's a separate conversation.

Use this structure:

~~~markdown
# Discovery Report

**Scenarios found:** {total count}

{For each scenario, in priority order:}

---

## {N}. {Scenario name}

{Description and value proposition — use the text from the tool result.}

**Importance:** {importance level}
**Affected projects:**
- `{full/path/to/ProjectA.csproj}`
- `{full/path/to/ProjectB.csproj}`
~~~

**That's it.** No "Recommendations" section, no "Resources" section, no "Current Status" section, no "Support Lifecycle" section. Only the scenarios and their data as returned by the tool.

Write it to the scenario folder as `discovery-report.md` if a scenario folder exists, or present it inline if no scenario is active. Confirm the path to the user after writing.
