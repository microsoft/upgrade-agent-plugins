# Assessment Stage Instructions

## ⛔ REQUIRED: Read This File Completely

This file contains **2 required steps** and **edge case handling**. You MUST read all sections before starting:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | Analyze Projects | Run analysis, handle security vulnerabilities |
| 2 | Present Assessment | Open assessment.md, show summary to user |
| - | Handling Edge Cases | No projects, already latest, unsupported types |
| - | Checklist | Final verification before planning |

**Do not start assessment work until you have read through Step 2 and the Checklist.**

---

## Goal

Analyze the target projects to create a comprehensive assessment for the upgrade.

## Entry Criteria

- Pre-initialization complete (handled by `scenario-initialization` skill)
- If git repo: source control set up — on the correct working branch
- `initialize_scenario` already called — working folder exists at `.github/upgrades/{scenarioId}/`
- Upgrade parameters confirmed and saved in `scenario-instructions.md` (target framework, and source/working branch if git repo)

## Exit Criteria

- `assessment.md` created in workflow folder
- **Guided mode**: User has reviewed and approved the assessment
- **Automatic mode**: Assessment summary surfaced to user; proceed to planning immediately without waiting for approval

---

## Step 1: Analyze Projects

*⚡ Continue reading - Step 2 contains the approval flow and edge case handling.*

> **Note**: Parameter gathering (target framework, source control) was handled during pre-initialization.
> The confirmed target framework is available in `scenario-instructions.md`.

### 1.1 Run Analysis

```
generate_dotnet_upgrade_assessment(inputMode="{solution|projects|folder}", paths="{paths}", targetFramework="{target}")
```

Set `inputMode` to `solution`, `projects`, or `folder` and pass the corresponding path(s) in `paths` (semicolon-separated for multiple projects). See the tool parameter descriptions for detailed guidance on choosing the mode.

Returns:
- Project dependency graph
- Current and proposed target frameworks
- Package analysis (current versions, suggested updates, vulnerabilities)
- Code metrics (LOC, file count)
- Identified risks and issues

### 1.2 Handle Security Vulnerabilities

If vulnerabilities are found, present them to the user and **include them in the upgrade by default**:

<response_template>
⚠️ **Security Vulnerabilities Detected**

| Package | Current Version | Vulnerability |
|---------|-----------------|---------------|
| Newtonsoft.Json | 12.0.1 | CVE-2024-xxxx |
| System.Text.Json | 6.0.0 | CVE-2024-yyyy |

These will be addressed as part of the upgrade.
</response_template>

**Override**: Only skip security fixes if the user explicitly says not to include them (e.g., "don't fix the security issues", "handle security separately"). If the user opts out, save that preference to `scenario-instructions.md` under User Preferences.

---

## Step 2: Present Assessment

*⚡ Continue reading - Edge case handling and final checklist follow this section.*

The `generate_dotnet_upgrade_assessment` tool creates `assessment.md` on disk. Do **not** rewrite, reformat, or supplement the generated file — it is complete as-is.

### 2.1 Open Assessment in Editor

Open `assessment.md` in the editor so the user can review it. Follow the **How to Open Files** fallback chain from the user-interaction skill.

### 2.2 Show Summary to User

Present the summary returned by `generate_dotnet_upgrade_assessment` and reference the full document.

**Check the flow mode** in `scenario-instructions.md`:

<response_template>
## Assessment Complete

I've analyzed the solution and created a full assessment — see [assessment.md]({link_to_file}).

{summary from generate_dotnet_upgrade_assessment tool response}

{if vulnerabilities found}
### Security Vulnerabilities ({N} total)

| Package | Severity | CVE |
|---------|----------|-----|
| {package} | {Critical|High|Medium} | {CVE-xxxx} |

These will be addressed as part of the upgrade.
{end if}
</response_template>

#### Guided Mode — block and wait

Append the following footer after the summary, then **wait for user approval**:

```
---
**To proceed:** `approve` or `continue`
**To adjust:** Edit assessment.md or tell me what to change
**To switch mode:** Say `continue in automatic mode` to stop pausing at stage boundaries
```

#### Automatic Mode — surface and proceed

After the summary, add a brief note that you're proceeding to planning. Remind the user they can pause the agent and ask it to switch to Guided mode at any time.

**Then immediately continue to the planning stage** — do not wait for user input.

---

## Handling Edge Cases

### No Projects Found

<response_template>
I couldn't find any .NET projects in the specified path.

**Checked**: {path}

Please specify the solution or project path directly.
</response_template>

### Already on Latest Framework

<response_template>
The project(s) are already on .NET {version}.

**Options**:
1. End this scenario
2. Proceed with package updates only
3. Target an even newer preview version

What would you like to do?
</response_template>

### Unsupported Project Types

<response_template>
Some projects cannot be automatically upgraded:

- **{project}**: {reason - e.g., "Uses legacy project format"}

**Options**:
1. Skip these projects and upgrade the rest
2. Manually convert first, then retry
3. End scenario

What would you like to do?
</response_template>

---

## Checklist Before Moving to Planning

- [ ] Analysis complete
- [ ] assessment.md created
- [ ] Security vulnerabilities documented (if any) — included in upgrade by default
- [ ] Assessment summary presented to user
