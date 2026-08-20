# Upgrade Options

Configurable upgrade decisions, loaded selectively during planning based on
what signals have surfaced about the solution.

> **Used by planning.md Step 1.5 and Step 2 only.**
> Step 1.5 loads them to evaluate options. After confirmation, Step 2 reopens only
> the sections named by a **Plan impact: Yes** row below.
> Do not load these files during assessment or execution.

---

## Option Files

Each option is a self-contained file with applicability conditions, default logic,
and recognized values. Only load the files whose trigger condition is met.

| Option | Category | File | Plan impact |
|--------|----------|------|-------------|
| Upgrade Strategy | Strategy | [strategy.md](strategy.md) | Yes — `Strategy Interaction`, `What is NOT configurable` |
| Project Approach | Project Structure | [project-approach.md](project-approach.md) | Yes — `Strategy Interaction` |
| Package Management | Project Structure | [package-management.md](package-management.md) | Yes — `What is NOT configurable` |
| Unsupported Packages | Compatibility | [unsupported-packages.md](unsupported-packages.md) | Yes — `What is NOT configurable` |
| Unsupported API Handling | Compatibility | [unsupported-api-handling.md](unsupported-api-handling.md) | Yes — `What is NOT configurable` |
| Windows Native APIs | Compatibility | [windows-native-apis.md](windows-native-apis.md) | No |
| System.Web Adapters | Compatibility | [system-web-adapters.md](system-web-adapters.md) | No |
| Cross-App Cookie Authentication | Compatibility | [cross-app-cookie-auth.md](cross-app-cookie-auth.md) | No |
| Configuration Migration | Modernization | [configuration-migration.md](configuration-migration.md) | No |
| Logging Framework | Modernization | [logging-framework.md](logging-framework.md) | No |
| Dependency Injection | Modernization | [dependency-injection.md](dependency-injection.md) | No |
| Assembly Binding Redirects | Modernization | [binding-redirects.md](binding-redirects.md) | No |
| Nullable Reference Types | Modernization | [nullable-reference-types.md](nullable-reference-types.md) | No |
| Entity Framework | Modernization | [entity-framework.md](entity-framework.md) | No |
| Test Coverage | Reliability | [test-coverage.md](test-coverage.md) | Yes — `Generate flow`, `Test Baseline`, `Generation failure` |

**Plan impact** says whether the file still matters after its value is confirmed.
**No** means the confirmed value is the whole story — the rest of the file is
applicability conditions, default logic, and alternatives, all of which are spent
once the user has chosen. **Yes** means the file also carries behavior the plan must
honor that the confirmed value alone does not convey — non-configurable rules,
cross-option interactions, or a named procedural flow. That behavior may itself be
conditional on the selected value (`test-coverage.md`'s `Generate flow` runs only for
**Generate**); what makes it **Yes** is that knowing the value is not enough to act.
The listed sections are the only parts worth reopening.

The index row is authoritative at runtime. Each option file also mirrors its marker on
a `**Plan impact**:` line in its header, next to `**Category**:`, as an authoring aid;
if the two ever disagree, the row above wins and the header is the bug.

Choice mechanics are **not** plan impact. When a selected value implies follow-up work
— deferred stubs, resolution subtasks — the task structure is owned by `execution.md`
Decomposition Rules and the `breakdown-hints/` files, not by reopening the option file.

---

## Trigger Index

Load options as follows:

- **Upgrade Strategy**: always load.
- **Test Coverage**: load whenever the assessment recommends Test Coverage, including for a Simple
  upgrade.
- **All other options**: load only for a Complex upgrade when their trigger condition is met (see planning.md).

Triggers describe **what** makes an option relevant. The “Likely source” column
hints at where evidence may come from — but any source is valid (assessment data,
project files, user input, tool output, conversation history). Do not proactively
inspect files just to check triggers; only load an option if the signal has already
surfaced.

| Trigger | Condition | Likely source | Option file |
|---------|-----------|---------------|-------------|
| Always | Every upgrade needs a strategy | — | [strategy.md](strategy.md) |
| Test Coverage recommended | Assessment recommends Test Coverage for at least one project | Assessment | [test-coverage.md](test-coverage.md) |
| .NET Framework project | Any project targets .NET Framework | Assessment, project files | [project-approach.md](project-approach.md) |
| Multiple projects without CPM | ≥ 2 projects and no centralized package management | Assessment, repo structure | [package-management.md](package-management.md) |
| Incompatible packages | Packages with no compatible version for the target TFM | Assessment | [unsupported-packages.md](unsupported-packages.md) |
| Breaking API changes | APIs removed or changed in the target TFM (binary or source incompatible) | Assessment | [unsupported-api-handling.md](unsupported-api-handling.md) |
| Windows-specific APIs | P/Invoke, Registry, System.Drawing, Win32 API usage | Assessment, code | [windows-native-apis.md](windows-native-apis.md) |
| System.Web / ASP.NET Framework | System.Web references, ASP.NET MVC or WebAPI on .NET Framework | Assessment, project files | [system-web-adapters.md](system-web-adapters.md) |
| Cookie-authenticated Framework web app | A .NET Framework web project authenticates browser requests with a cookie — Forms authentication, OWIN/Katana cookie middleware, ASP.NET Identity sign-in, or a `machineKey`-protected authentication cookie. A `machineKey` entry alone is not enough; it commonly protects only ViewState | Assessment, project files, config, user input | [cross-app-cookie-auth.md](cross-app-cookie-auth.md) |
| Complex configuration | Custom config sections, transforms, encrypted settings, high key count | Project files, user input | [configuration-migration.md](configuration-migration.md) |
| Third-party logging | log4net, NLog, ELMAH, Common.Logging in use | Assessment, project files, user input | [logging-framework.md](logging-framework.md) |
| Third-party DI container | Autofac, Unity, Ninject, Castle Windsor, StructureMap, SimpleInjector in use | Assessment, project files, user input | [dependency-injection.md](dependency-injection.md) |
| Binding redirects | assemblyBinding entries in config files | Project files, user input | [binding-redirects.md](binding-redirects.md) |
| Nullable not enabled | Target is net5.0+, C# project, nullable not already enabled | Project files | [nullable-reference-types.md](nullable-reference-types.md) |
| Entity Framework 6 | EF6 6.x in use and target is net5.0+ | Assessment, project files | [entity-framework.md](entity-framework.md) |

---

## How to Evaluate Options

For each loaded option file:

1. **Evaluate the Applicability Condition** against available evidence
2. **If not applicable** — skip entirely (do not mention it anywhere)
3. **If applicable** — evaluate the Default Logic to determine recommendation
4. **Add it to the confirmation payload** using the schema below

Keep evaluation reasoning internal — do not write reasoning to any file or to the chat.

There is **no options file**. Options are carried as a structured payload until the
user confirms them, then recorded in `scenario-instructions.md` (live source of
truth) and `plan.md` (durable record). Never write an `upgrade-options.md`.

---

## Confirmation Payload

Applicable options are carried as a **structured payload**, not a file. This one
payload feeds every confirmation path — the interactive form, the chat-rendered
text, and the re-dispatch that follows confirmation.

Include only applicable options. Never mention non-applicable options anywhere.

```json
{
  "solutionName": "{solution name}",
  "assessmentSummary": "{one line: project count, frameworks, key signals}",
  "sections": [
    {
      "id": "strategy",
      "name": "Strategy",
      "options": [
        {
          "id": "upgrade-strategy",
          "name": "Upgrade Strategy",
          "rationale": "{one sentence citing a specific assessment finding}",
          "selected": "{selected value}",
          "choices": [
            { "value": "{selected value}", "description": "{what happens when selected}" },
            { "value": "{alternative}", "description": "{what happens when selected}" }
          ]
        }
      ]
    }
  ]
}
```

Rules:
- `selected` must exactly match one of the `choices[].value` entries
- `rationale` is **required** on every option, no exceptions — in text-based hosts
  it is the only explanation the user sees. One sentence citing a specific
  assessment finding. Never omit it, never leave it empty, and never fold it into
  the `selected` value
- Every choice needs a short single-sentence `description`, taken from the option
  file's **Options** section (not the full paragraph)
- Sections appear in this order, omitting any with no applicable options:
  Strategy, Project Structure, Compatibility, Modernization, Reliability
- Strategy is always present and always first

---

### Rendering the payload as text

Hosts without an interactive options form present the payload in chat. Render it as
**one compact block**, then ask a **single** combined question — never one question
per option.

Every option sits under its section heading, and every alternative is indented one
level below its option and prefixed `Alternative — `:

```markdown
**Upgrade Options** — {solutionName}

**{Section Name}**
- **{Option Name}**: {selected value} — {rationale}
  - Alternative — {other value}: {description}
```

Worked example — follow this layout exactly:

```markdown
**Upgrade Options** — Contoso.sln

**Strategy**
- **Upgrade Strategy**: Bottom-Up — Multiple Framework projects require dependency-ordered migration.
  - Alternative — Top-Down: Start at entry-point projects and migrate their dependencies as needed.

**Project Structure**
- **Web Projects**: Side-by-side — Keeps the high-risk web app available during incremental migration.
  - Alternative — In-place rewrite: Replace the Framework web project entirely in one pass.
- **Class Libraries**: Multi-targeting — Supports Framework and Core consumers during transition.
  - Alternative — In-place: Replace the TFM directly, requiring consumers to migrate first.
  - Alternative — Duplicate project: Keep a parallel Core project beside the Framework one.

**Modernization**
- **Logging**: Microsoft.Extensions.Logging — log4net has no supported .NET 10 package in this solution.
  - Alternative — Keep the existing framework: Retain log4net behind an adapter package.
```

Rules:
- **Always group by section.** Print the section name in bold on its own line, then
  its options beneath it. Never flatten everything into one undifferentiated list,
  even when a section holds a single option.
- One line per option: bold option name, then the selected value, then ` — ` and the
  rationale. **The rationale is mandatory on every line** — never print an option
  that stops at its value, and never pass off a restatement of the value as a
  reason. This holds even when the value looks self-explanatory: a selection like
  `Microsoft.Extensions.Logging` still needs a reason tied to the assessment,
  because the user is judging the choice, not decoding the name.
- Print no preamble between the title and the first section heading — in particular
  do not render `assessmentSummary` here. It belongs to the interactive form only.
- **Print every non-selected choice as an alternative — never omit them.** The
  alternatives are how the user learns what they can switch to; an option whose
  alternatives are hidden is an option they cannot meaningfully change. An option
  with N `choices` prints N-1 sub-bullets.
- **Every alternative is an indented sub-bullet prefixed `Alternative — `.** Without
  that prefix and indent the reader cannot tell an alternative apart from the next
  option — the single most common rendering mistake.
- Use each alternative's `description` **verbatim** — never invent or embellish.
- Do not list the selected value among the alternatives. Only an option whose
  `choices` holds exactly one entry prints no sub-bullets.
- Plain text only — no HTML entities or tags; indent with real spaces or `-` bullets
  so it renders in a terminal.
- Follow with one combined question: confirm everything, or say what to change.

Before sending, check every option line: it sits under a bold section heading, it
ends with ` — ` plus a rationale, and it is followed by one `Alternative — ` bullet
for every remaining entry in its `choices`. Fix any line that fails before printing.

**Put the block in your chat message — never inside the question tool.** Interactive
question UI is dismissed the moment the user answers, so anything rendered inside it
is gone: a user who picks "change something" is left with nothing to refer to. Print
the full block as your visible response **first**, then call the question tool with
only a short prompt (e.g. "Confirm these upgrade options?") and its choices. Never
put option names, values, rationales, or alternatives into the question text or the
choice labels.

**Re-print the whole block every round.** If the user changes something, print the
complete updated block again — with their change applied — before asking the next
question. Never ask a follow-up about options the user can no longer see.

---

### plan.md `## Upgrade Options` section

`plan.md` is written only after every option is confirmed, so this section records the
final confirmed set. It is **written once and never mutated** — later changes go to
`scenario-instructions.md`, which is the live source of truth.

```markdown
## Upgrade Options

| Option | Selected | Why |
|--------|----------|-----|
| {Option Name} | {confirmed value} | {rationale} |
```

One row per confirmed option, in payload order. Omit the section entirely if no
options were applicable.

---

### scenario-instructions.md compact block

After the user confirms, write the confirmed selections as this compact block in
`scenario-instructions.md`. This is the **live source of truth** — it is always in
context while the workflow is active, and the execution stage reads options only
from here.

```markdown
## Upgrade Options

### Strategy
- Upgrade Strategy: {selected value}

### Project Structure
- Project Approach: {selected value}
- Package Management: {selected value, only if applicable}

### Compatibility
[one line per applicable option only]
- Unsupported Packages: {selected value} ({N} incompatible packages)
- Unsupported API Handling: {selected value}
- Windows Native APIs: {selected value}
- System.Web Adapters: {selected value}
  Skill: migrating-mvc-system-web-adapters [only when "Use System.Web Adapters" selected]
- Cross-App Cookie Authentication: {selected value}
  Skill: sharing-authentication-cookies-katana-interop [only when "Shared Cookie (Data Protection interop)" selected]

### Modernization
[one line per applicable option only]
- Configuration Migration: {selected value}
- Logging Framework: {selected value}
- Dependency Injection: {selected value}
- Assembly Binding Redirects: {selected value}
- Nullable Reference Types: {selected value}
- Entity Framework: {selected value}

### Reliability
[only if applicable]
- Test Coverage: {selected value}
```

Rules for writing this block:
- Omit headings whose options are all non-applicable
- Never write a placeholder — use actual confirmed values
- An option that carries a `Skill:` sub-line gets that sub-line only when its confirmed
  value matches the condition in brackets. An option may bind a skill to only some of its
  values, so write the one sub-line whose condition matches and drop the rest; write none
  if no condition matches. Copy the value into the condition **verbatim** from the option
  file's **Options** list — an abbreviated value stops matching
- A `Skill:` sub-line is what turns a skill into a standing load, so write it only from the
  option file that owns that skill. Never add one for a value whose guidance a different
  option already loads — that forces the skill in even when the owning option's value says
  it should stay out
- Custom options (from user-provided skills) go under their declared category heading

---

## Custom Upgrade Options

Users can extend the built-in options by adding `upgrade-option: {Name}` to any
custom skill's description. During Step 1.5, the agent scans Available Skills
descriptions for this prefix — only matching skills are loaded.

A matching skill must contain an `## Upgrade Option` section:

```markdown
## Upgrade Option

**Option Name**: {unique name}
**Category**: {Project Structure | Compatibility | Modernization | Reliability}
**Plan impact**: {No | Yes — `Section Name`, `Other Section`}

**Applicable when**:
- {assessment signal condition}

**Not applicable when**:
- {condition}

**Default logic**:
- Recommend **{value}** if: {condition}

**Options**:
- **{Value A}** — {description}
- **{Value B}** — {description}

**Stored as**: `Upgrade Options > {Category} > {Option Name}`
```

Custom options go under their declared category section in the confirmation payload
and the compact block. The category determines which section the option appears in.
If a custom option duplicates a built-in option name, the custom option wins.

A custom option has no row in the table above, so its `**Plan impact**:` line is the
only signal available and Step 2 reads it directly from the skill. Declare it — a
precise `No`, or a `Yes` naming the sections, keeps the reopen narrow. An omitted
marker is treated as **Yes**, so Step 2 falls back to reading the whole
`## Upgrade Option` section: safe, but wasteful.
