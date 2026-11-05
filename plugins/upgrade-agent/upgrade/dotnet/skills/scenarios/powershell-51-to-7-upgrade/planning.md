# Stage 2: Planning

Turn the assessment into an ordered, executable plan. Two things drive the order:
**blocker class** (mechanical before architectural) and **dot-source dependency
direction** (libraries before callers).

> **File format is enforced by the system `plan-generation` skill.** Load and follow it
> for the exact templates for `plan.md` and `scenario-instructions.md`. This scenario
> file defines **what** to plan; the `plan-generation` skill defines **how** to write the
> artifacts.

## Entry Criteria

- `assessment.md` exists and has been reviewed.

## Exit Criteria

- `plan.md` created with ordered tasks (per the `plan-generation` plan.md template).
- Execution constraints (`targetPowerShellVersion`, resolved PSScriptAnalyzer profile,
  platform intent, Advisory policy) persisted in `scenario-instructions.md`.
- **No `tasks.md` on disk** — it is generated in code by `start_task`. See the
  `plan-generation` skill.

## Steps

### Step 1 — Bucket the findings

Group findings by blocker class. Each class has one remediation lazy skill, so a class
is the natural task boundary:

| Bucket | Lazy skill (write this marker verbatim into the task) | Character |
|---|---|---|
| Mechanical auto-fixes | `#skill:powershell-mechanical-fixups` | Deterministic rewrite |
| WMI → CIM | `#skill:migrating-wmi-to-cim` | Mechanical + shape change |
| EventLog → WinEvent | `#skill:replacing-eventlog-with-winevent` | Semantic; enum remap |
| Removed snap-ins | `#skill:handling-removed-snapins` | Architectural |
| Exchange management shell | `#skill:migrating-exchange-management-shell` | Architectural; hardest |
| Windows-only modules | `#skill:fixing-windows-only-modules` | Platform decision |

Every task additionally carries `#skill:scanning-powershell-compatibility`, because
execution's per-task gate is a re-scan (see [execution.md](execution.md) §3).

The `#skill:` prefix is not decoration: task execution scans the task body for it and
surfaces that skill on the task automatically. Execution then loads the body with
`get_instructions(kind='skill', query='<name>')`, which is an exact-name lookup. Naming
the skill in prose instead leaves the match to a relevance ranker competing against
every other skill in the catalog, which is how a task ends up remediating WMI without
the CIM mapping table in front of it.

Mechanical auto-fixes cover `-Encoding Byte` → `-AsByteStream`, `powershell.exe` →
`pwsh`, `New-WebServiceProxy` removal, `#Requires` bump, and safe `$null`-on-left
rewrites.

**One task class does not come from the findings.** Assessment Step 2a classifies
each pinned module as Native, Shimmed, or Blocked. Every module that is not Native
and has a newer version that is becomes its own task, carrying
`#skill:fixing-windows-only-modules`. These are invisible to the scan — the
findings describe what the scripts *say*, not whether the modules they import can
load — so nothing else in this stage will surface them.

Where no version loads natively, do not raise a task. Record it as an accepted
constraint under Step 5 and carry it into the plan as a known limitation.

### Step 2 — Order the work

1. **Module pin raises first.** They change the command surface the profile
   describes, so the profile is regenerated and the baseline re-taken afterwards.
   Every file task sequenced before a pending bump is validated against a profile
   that no longer matches the environment, which has to be redone.
2. **Mechanical auto-fixes.** Low-risk and high-volume; they shrink the noise
   before the hard work, so later diffs are readable.
3. **WMI → CIM**, then **EventLog → WinEvent**.
4. **Removed snap-ins**, and specifically **Exchange management shell** — the
   architectural bucket, planned last so the rest of the estate is already clean.
5. **Windows-only modules**, resolved against the confirmed platform intent.

Within every bucket, **dot-sourced libraries come before their callers**. Where a
library and its callers are large enough to warrant separate tasks, make the caller
task depend on the library task and re-scan callers after the library changes.

#### Under partial scope this order inverts for shared files

The order above assumes the whole estate lands on PS7 together. It does not hold for
a file that is dot-sourced by callers left on 5.1 (identified in
[assessment.md](assessment.md) Step 4): that file must keep running on **both**
hosts, and the mechanical bucket is precisely the one that breaks it. Verified
against a 5.1 host:

| Remediation | Runs on 5.1? | Bucket |
|---|---|---|
| `Get-CimInstance` / `Invoke-CimMethod` | Yes (since PS3) | WMI → CIM |
| `Get-WinEvent` / `New-WinEvent` | Yes (since PS2) | EventLog |
| `$null -eq $x` rewrite | Yes | Mechanical |
| `-Encoding utf8` / `ascii` / `unicode` | Yes | Mechanical |
| `-AsByteStream` | **No** — parameter does not exist | Mechanical |
| `-Encoding utf8BOM` / `utf8NoBOM` / `ansi` | **No** — not in the 5.1 enum | Mechanical |
| `pwsh` replacing `powershell.exe` | **No** — not installed on a 5.1-only host | Mechanical |
| `#Requires -Version 7` / `-PSEdition Core` | **No** — 5.1 refuses to run the file | Mechanical |
| `Import-Module -UseWindowsPowerShell` | **No** — parameter does not exist | Windows-only modules |

So for shared files: do the **architectural** buckets first (they are the
bi-compatible ones) and defer every row marked **No** until the callers migrate.
Leave those findings open with a recorded reason rather than "fixing" them — a
one-way fix in a shared library breaks working 5.1 scripts the user never asked you
to touch, and it fails at runtime, not at edit time.

Files entirely inside the selection have no out-of-scope callers and follow the
normal order. Split a bucket along that line when it contains both.

### Step 3 — Decide the Advisory policy

Advisory findings (e.g. `$x -eq $null`) still work on PS7. Decide with the user whether
to fix them as one optional batch task at the end, or skip them. Either way they are
**not** a completion gate — record the decision in `scenario-instructions.md`.

### Step 4 — Build the plan

Create `plan.md` using the **`plan-generation` system skill's template**. One task per
bucket (split per subtree or per library when a bucket is large):

```
### {NN}-{slug}: {task name}

{1-3 paragraph intent-based description: which blocker ids, which files or file
group, and what the remediation is. Include the bucket's `#skill:` marker verbatim.}

**Done when**: {verifiable success criteria, including the re-scan result and the
validation rung the files must reach.}
```

Use canonical `NN-slug` task IDs (two-digit zero-padded sequence + kebab slug, e.g.
`01-mechanical-fixups`, `04-remove-snapins`) as required by the `plan-generation`
system skill — never `T-01` or other letter-prefixed ids, or task tracking will break.

For each task record:
- The blocker id(s) it clears, so execution can query `scan-findings.csv` for exact
  locations.
- The file set (a subtree, a library + its callers, or an explicit list). Set
  `TargetProject` to the script path or folder the task covers.
- The `#skill:` marker for the bucket, written verbatim into the task body.
- Whether the task's files must stay **5.1-compatible** (any file with out-of-scope
  callers), and which findings are therefore deferred.
- The validation rung the files must reach (see [validation-ladder.md](validation-ladder.md)).

Size tasks so one task is one coherent remediation pass, not one file. A repo with
thousands of scripts still produces a handful of tasks — use `break_down_task` during
execution when a bucket turns out to be too big to land in one pass.

### Step 5 — Persist constraints

Write a compact block to `scenario-instructions.md`: `targetPowerShellVersion`, the
resolved PSScriptAnalyzer compatibility profile id (or a note that it could not be
resolved), platform intent (Windows-only vs cross-platform), the Advisory policy, and
any paths the scan could not read. Execution reads this.

When scope is partial, add: the closed selection, the files that must stay
5.1-compatible, and the findings deferred for that reason. Without this, a later
session re-scans, sees an open `-Encoding Byte` finding in a shared library, and
"fixes" it — reintroducing exactly the break this stage decided against.

Never touch the `## Source Control` section — it is owned by pre-init and `branch-sync`.

## Transition to Execution

After `plan.md` and `scenario-instructions.md` are created and presented (via the
`plan-generation` skill):

- **Guided mode**: wait for user approval before proceeding. Do not load `execution.md`
  yet.
- **Automatic mode**: **immediately** load [execution.md](execution.md) and begin the
  first task. The plan has been surfaced — proceed.
