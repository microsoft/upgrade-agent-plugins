---
name: creating-skills
description: >
  Create, validate, and iteratively improve agent skills that follow Anthropic's best practices.
  Use this skill whenever someone wants to create a new skill, improve an existing skill, write a
  SKILL.md, set up a skill directory structure, or needs guidance on skill authoring patterns. Also
  triggers when users mention "custom instructions", "agent skill", "skill template", or want to
  codify a workflow into a reusable skill. This skill enforces a create-validate-improve loop that
  produces production-ready skills passing code review on the first submission.
---

# Creating Skills — Author, Validate, Improve

This skill guides you through producing agent skills that follow Anthropic's official best practices. It enforces an iterative loop: draft → validate → improve → re-validate, until the skill meets all quality criteria.

## When to read additional files

- **First time authoring or need the full checklist?** → Read [references/quality-checklist.md](references/quality-checklist.md)
- **Need to validate an existing skill?** → Read [references/validation-rules.md](references/validation-rules.md)
- **Run automated checks?** → `scripts/validate_skill.ps1` (Windows) or `scripts/validate_skill.sh` (Linux/macOS)
- **Want a blank starting point?** → Read [templates/SKILL-TEMPLATE.md](templates/SKILL-TEMPLATE.md)
- **Need to understand the principles behind these rules?** → Read [references/anthropic-best-practices.md](references/anthropic-best-practices.md)

---

## The Core Loop

Every skill goes through this cycle. Your job is to figure out where the user is and help them progress.

```
┌──────────────┐
│  0. DISCOVER │  Scan for existing skills that overlap
│              │
└──────┬───────┘
       ▼
┌──────────────┐
│  1. CAPTURE  │  Understand what the skill should do
│     INTENT   │  
└──────┬───────┘
       ▼
┌──────────────┐
│  2. DRAFT    │  Write SKILL.md + directory structure
│              │
└──────┬───────┘
       ▼
┌──────────────┐
│  3. VALIDATE │  Run checklist against the draft
│              │  (read references/validation-rules.md)
└──────┬───────┘
       ▼
┌──────────────┐     ┌──────────────┐
│  4. TEST     │---->│  5. IMPROVE  │
│  (optional)  │     │  based on    │
│              │<----│  findings    │
└──────┬───────┘     └──────────────┘
       ▼                    │
   Passes all?              │
   User happy? <------------┘
       ▼
┌──────────────┐
│  6. PACKAGE  │  Final structure, ready for repo
└──────────────┘
```

---

## Step 0: Discover Existing Skills

Before creating a new skill — or even before capturing intent in detail — scan for existing skills that might already cover the need.

### How to scan

1. **Find all SKILL.md files** across the skill directories declared in the repo's copilot-instructions.md (or scan recursively from the repo root):
   ```bash
   find . -name "SKILL.md" -type f
   ```

2. **Extract frontmatter** from each — just the `name` and `description` fields. Build a compact inventory:
   ```
   migrating-wcf-to-corewcf | Migrates WCF services from .NET Framework to CoreWCF...
   managing-target-frameworks | Manages target frameworks in .NET project files...
   ```

3. **Compare the proposed skill** against the inventory on three dimensions:
   - **Name conflict** — exact match is a hard block; similar names (e.g., `processing-pdfs` vs `pdf-processing`) are a warning
   - **Description overlap** — high keyword overlap between descriptions signals a likely duplicate
   - **Trigger phrase collision** — if two skills mention the same file types, APIs, or user phrases in their descriptions, they will compete for the same queries

4. **Report findings** before proceeding:
   - If an existing skill fully covers the need → recommend using it instead
   - If an existing skill partially covers the need → recommend extending it or referencing it
   - If overlap is minor → note it and proceed with the new skill
   - If no overlap → proceed

### When improving an existing skill

Still run the scan — the improved skill's new description or triggers might now overlap with another skill that didn't overlap before. Check specifically for trigger phrase collisions after editing descriptions.

### Skip conditions

Skip this step only when the user explicitly says "I know there's no overlap" or when the skill name was provided by the user as a deliberate choice.

## Step 1: Capture Intent

Start by understanding what the user wants. If the current conversation already contains a workflow they want to capture ("turn this into a skill"), extract answers from context first.

Gather these essentials (ask only what's missing):

1. **What should this skill enable Claude to do?** — The core capability.
2. **When should it trigger?** — User phrases, file types, contexts.
3. **What's the expected output?** — File types, formats, or behaviors.
4. **What does "good" look like?** — Success criteria the user cares about.
5. **Does it need scripts or just instructions?** — Pure markdown vs. code-assisted.
6. **Who is the audience?** — Other developers? Non-technical users? Both?

Don't over-interview. If you have enough to draft, draft. You can refine later.

## Step 2: Draft the Skill

Read [templates/SKILL-TEMPLATE.md](templates/SKILL-TEMPLATE.md) for the starting structure.

The frontmatter includes `name`, `description`, and an optional `metadata` block with `traits` (pipe-separated technology tags) and `discovery` (e.g., `lazy` for on-demand loading). See the template for the exact format.

### Key principles while drafting

**Conciseness is non-negotiable.** Claude is already smart. Only add context Claude doesn't already have. For every paragraph, ask: "Does this justify its token cost?"

**Match freedom to fragility:**
- High freedom (guidelines) → when multiple approaches are valid
- Medium freedom (pseudocode) → when a preferred pattern exists
- Low freedom (exact scripts) → when operations are fragile or order matters

**Write descriptions in third person.** The description is injected into a system prompt. "Processes Excel files and generates reports" — not "I can help you" or "You can use this to."

**Make descriptions pushy.** Skills tend to under-trigger. Include both what the skill does AND when to use it, with specific trigger phrases and contexts.

**Use language-neutral terminology.** Say "project file" instead of `.csproj` when the context applies to any .NET project type (C#, VB.NET, F#). Only use specific extensions when the context is truly language-specific.

**Explain the why.** Instead of rigid MUSTs in all caps, explain reasoning. Claude responds better to understanding intent than to blunt force rules.

### Directory structure

```
skill-name/
├── SKILL.md              # Required. Under 500 lines.
├── references/           # Optional. Detailed docs loaded on demand.
│   ├── some-domain.md
│   └── another-domain.md
├── scripts/              # Optional. Executable utilities.
│   ├── validate.py
│   └── helper.sh
├── templates/            # Optional. Output templates.
└── assets/               # Optional. Fonts, icons, images.
```

### Naming rules

**Format:** lowercase letters, numbers, hyphens only. Max 64 chars. No reserved words ("anthropic", "claude").

**Choosing a good name — lead with a gerund verb:**

The name should answer "what does this skill do?" in 2-5 hyphenated words. Start with a gerund (verb ending in -ing) that describes the primary action:

| Action type | Pattern | Examples |
|-------------|---------|----------|
| Migration (A→B) | `migrating-{source}-to-{target}` | `migrating-wcf-to-corewcf`, `migrating-newtonsoft-to-system-text-json` |
| Migration (general) | `migrating-{what}` | `migrating-aspnet-identity`, `migrating-global-asax` |
| Conversion | `converting-to-{target}` | `converting-to-sdk-style` |
| Management | `managing-{what}` | `managing-target-frameworks`, `managing-package-references` |
| Integration | `integrating-{what}` | `integrating-autofac-with-dotnet` |
| Modification | `modifying-{what}` | `modifying-project-properties` |

**Naming anti-patterns:**
- ❌ Noun-only: `msmq-migration` → ✅ `migrating-to-msmq-messaging`
- ❌ Redundant suffix with gerund: `migrating-aspnet-identity-migration` → ✅ `migrating-aspnet-identity`
- ❌ Vague: `helper`, `utils`, `tools`, `data`, `files`
- ❌ Technology dump: `system-security-cryptography-migration` → ✅ `migrating-cryptography-namespaces`

**Exception — scenario and system skills:** Gerund naming applies to production and agent skills. Scenario skills (`discovery: scenario`) are multi-stage workflow orchestrators — use noun-form names that describe the workflow: `dotnet-version-upgrade`, not `upgrading-dotnet-version`. System skills (`discovery: system`) are infrastructure capabilities loaded by the system prompt — use noun-form names that describe the concern: `state-management`, `plan-generation`, `task-execution`.

### Description rules
- Max 1024 characters. Must be non-empty.
- No XML tags.
- Third person only.
- Include trigger phrases and contexts.
- Be specific: "Extract text and tables from PDF files, fill forms, merge documents" — not "Helps with documents."
- **No cross-references in descriptions.** Descriptions are for triggering — mentioning another skill's name pollutes keyword matching and wastes the character budget. Put cross-references in the skill body instead (e.g., a `> **Related skill:**` callout in the Overview section).
- This project uses custom `metadata` frontmatter fields (`traits`, `discovery`) for skill routing. Preserve these when improving existing skills. Include them when creating new skills.

## Step 3: Validate

This is where most skill authoring fails — people skip validation entirely.

Read [references/validation-rules.md](references/validation-rules.md) and run every check against the draft. Start with the automated validator to catch structural issues:

```powershell
# Windows (PowerShell)
.\scripts\validate_skill.ps1 .\path\to\skill
```

```bash
# Linux / macOS / CI
bash scripts/validate_skill.sh ./path/to/skill
```

Both scripts check the same rules and produce the same scorecard. The automated checks cover structure, frontmatter, line counts, paths, and reference depth. The full validation also includes subjective checks that need human review:

1. **Structure** — Frontmatter, file organization, line counts
2. **Content quality** — Conciseness, freedom calibration, terminology consistency
3. **Description effectiveness** — Trigger coverage, specificity, third person
4. **Progressive disclosure** — Reference depth, file organization
5. **Code quality** (if applicable) — Error handling, no magic numbers, dependency listing
6. **Anti-patterns** — Windows paths, too many options, time-sensitive info, nested references

Present findings to the user as a scorecard:

```
Skill Validation Report: [skill-name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Structure         — Frontmatter valid, 127 lines
✅ Description       — Specific, third-person, trigger phrases included
⚠️  Conciseness      — Lines 45-62 explain what Claude already knows
❌ Progressive disc. — References nested 2 levels deep (max 1)
✅ Terminology       — Consistent throughout
⚠️  Code quality     — scripts/helper.py has unexplained TIMEOUT=47
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Result: 2 issues to fix before this passes review
```

## Step 4: Test (when applicable)

Testing is optional but recommended for skills with objectively verifiable outputs.

Create 2-3 realistic test prompts — things a real user would actually say. Not abstract placeholders, but concrete requests with file names, context, and detail. Share them with the user for confirmation.

For each test prompt:
1. Follow the skill's instructions yourself to complete the task
2. Check if the output matches the skill's stated success criteria
3. Note where instructions were unclear, missing, or led you astray

If the skill has scripts, actually run them and verify they work.

## Step 5: Improve

Based on validation findings and test results:

1. **Generalize, don't overfit.** If a test case revealed a gap, fix it in a way that handles the general class of problems, not just that specific case.
2. **Keep it lean.** Remove anything that isn't pulling its weight. If a section didn't help during testing, cut it.
3. **Explain the why.** If you find yourself writing "ALWAYS" or "NEVER" in caps, reframe it as reasoning. "Because XML validation is fragile and errors cascade, validate after every edit" beats "ALWAYS VALIDATE."
4. **Bundle repeated work.** If you found yourself writing the same helper code across test cases, that's a script the skill should bundle.

After improving, go back to Step 3 (Validate) and run the checklist again. Repeat until clean.

## Step 6: Package

Final checks before the skill is ready:

1. All validation rules pass
2. SKILL.md is under 500 lines
3. Reference files longer than 100 lines have a table of contents
4. All file paths use forward slashes
5. Scripts have explicit error handling
6. No time-sensitive information (or it's in an "old patterns" section)
7. Dependencies are listed with install commands

Present the final directory structure to the user and confirm it's ready for their repo.

---

## Special Scenarios

### Scenario skills with time-sensitive data

Scenario skills that reference technology versions, release status, or support lifecycle dates should include a `## Current Facts` section. This section provides authoritative grounding data that the agent uses instead of potentially stale training knowledge.

**Convention:**
- Section must be named exactly `## Current Facts`
- Place it near the top of the SKILL.md (after the scenario overview)
- Include a `<!-- Last updated: YYYY-MM-DD -->` comment for freshness tracking
- Content should be a table of verifiable facts (versions, dates, status)
- No opinions or recommendations — just facts
- Add a staleness check callout for items that may change (e.g., versions marked "Preview")

Example:
```markdown
## Current Facts

<!-- Last updated: 2025-11-12 -->

| Version | Status | Support Level | End of Life |
|---------|--------|---------------|-------------|
| .NET 10 | GA | LTS | 2028-11-14 |
| .NET 9 | GA | STS | 2026-11-10 |
| .NET 11 | Preview | — | 2030-11-12 (projected) |

> **Staleness check:** If the user asks about a version listed as **Preview** above,
> verify its current status using an internet search tool before answering —
> it may have shipped since this data was last updated.
```

The system prompt's Freshness Rule directs the agent to consult this section before answering version/lifecycle questions from training memory.

### "Turn this conversation into a skill"

The user has been working through a problem and wants to capture the workflow. Extract from the conversation:
- Tools and commands used
- Sequence of steps taken
- Corrections the user made (these are especially valuable — they reveal edge cases)
- Input/output formats observed
- Domain knowledge the user provided

Draft a skill from this, then validate normally.

### "Improve this existing skill"

Copy the skill to a writable location. Read it carefully. Run validation. Present the scorecard. Fix issues iteratively. Preserve the original name.

### "I just want a quick skill, skip the process"

Respect the user's time. Draft it, run a quick mental validation for the most critical rules (description quality, line count, no anti-patterns), mention any red flags, and deliver. You can always improve later.

---

## Communicating with the User

Pay attention to the user's technical level. Some users building skills are experienced engineers; others are discovering what a terminal is for the first time.

- Default to clear, jargon-lite language
- If the user shows strong technical signals, match their level
- Briefly explain terms like "frontmatter", "progressive disclosure", or "YAML" if there's any doubt
- Never condescend — just be clear
