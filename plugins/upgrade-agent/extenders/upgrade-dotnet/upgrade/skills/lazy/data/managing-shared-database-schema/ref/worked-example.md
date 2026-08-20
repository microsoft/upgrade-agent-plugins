# Worked Example: Renaming a Column While Both Hosts Are Live

Goal: `Users.EmailAddress` → `Users.Email`, with the .NET Framework host and the new .NET
host both serving production traffic against the same database.

A rename is **not** a rename. It is seven deployments. The ordering below is load-bearing:
swapping steps 2 and 3 silently loses data.

## Contents

1. [Phase 1 — Expand](#phase-1--expand) — add the nullable column
2. [Phase 2 — Dual-write](#phase-2--dual-write-before-any-backfill) — every writer, before any backfill
3. [Phase 3 — Backfill](#phase-3--backfill) — race-safe, restartable, batched
4. [Phase 4 — Verify](#phase-4--verify) — prove continuous equality
5. [Phase 5 — Read switch](#phase-5--read-switch) — new column with old-column fallback
6. [Phase 6 — Enforce](#phase-6--enforce) — constraints last; dual-write continues
7. [Phase 7 — Contract](#phase-7--contract) — stop old writes and drop the old column, only after every consumer is retired
8. [Summary](#summary)

## Phase 1 — Expand

Add the new column, nullable. Nothing reads or writes it yet.

```sql
ALTER TABLE dbo.Users ADD Email nvarchar(256) NULL;
```

Apply this **through the schema owner's toolchain — not by hand as well**. If EF6 owns the pen,
the `AddColumn` migration shown below *is* how this DDL reaches the database. Running the
`ALTER TABLE` manually and then applying the owner's migration tries to add the column twice
and fails.

Nullable is required: the legacy host's `INSERT` does not know the column exists, so a
`NOT NULL` column without a default would fail every legacy insert immediately.

Deploy this alone. Both hosts must stay healthy before continuing.

### Bindings

Add the property to both models, mapped explicitly to the new column. Neither model is the
source of truth for the schema — the DDL above is.

```csharp
// EF6 (schema owner — the migration is scaffolded here)
public string Email { get; set; }
// Migrations/202401011200_AddUserEmail.cs
AddColumn("dbo.Users", "Email", c => c.String(maxLength: 256));

// EF Core (read-projection — never scaffolds while EF6 owns the pen)
public string? Email { get; set; }
builder.Property(u => u.Email).HasColumnName("Email").HasMaxLength(256);
```

## Phase 2 — Dual-write *(before any backfill)*

Deploy to **every writer**: both web hosts, every background job, every admin tool, every
import script. Each write sets both columns.

```csharp
user.EmailAddress = value;   // old — still authoritative for reads
user.Email        = value;   // new — populated from now on
```

Prefer setting both in one place — a property setter, a domain method, or a `SaveChanges`
override — so a caller cannot update one and forget the other.

```csharp
// Centralised: callers cannot get it wrong
public string EmailAddress
{
    get => _emailAddress;
    set { _emailAddress = value; Email = value; }
}
```

**This phase must complete everywhere before Phase 3 begins.** Any writer still on the old
code writes `EmailAddress` and leaves `Email` NULL. If the backfill has already passed that
row, the value is lost — it will never be picked up again.

Confirm from the schema-writer inventory that every writer is deployed. Do not rely on
"the two web apps" — jobs and tools are writers too.

## Phase 3 — Backfill

Only now. Batched, restartable, and race-safe.

```sql
DECLARE @BatchSize int = 1000;
WHILE 1 = 1
BEGIN
    UPDATE TOP (@BatchSize) dbo.Users
    SET Email = EmailAddress
    WHERE Email IS NULL AND EmailAddress IS NOT NULL;

    IF @@ROWCOUNT < @BatchSize BREAK;
    WAITFOR DELAY '00:00:01';   -- let other traffic through
END
```

Why this is safe:

- **`WHERE Email IS NULL`** — never overwrites a value the dual-write just set. This is what
  makes it race-safe against live traffic, and it is why Phase 2 must come first.
- **Batched with a delay** — *reduces the risk of* lock escalation and avoids one long-running
  transaction. It does not eliminate escalation: escalation triggers on lock count and memory
  pressure, a single statement can take more than one lock per row, and the delay falls
  *between* statements so it cannot help within one. Keep the batch well under the ~5,000-lock
  threshold rather than at it, and watch for blocking as you tune.
- **Restartable** — the predicate is the progress marker. Kill it and re-run; it resumes.

## Phase 4 — Verify

Prove convergence before changing any read path.

```sql
-- Must be 0, and must stay 0 across several checks: rows the backfill has not reached
SELECT COUNT(*) FROM dbo.Users
WHERE Email IS NULL AND EmailAddress IS NOT NULL;

-- Must be 0: a writer updating one column without the other.
-- Written NULL-safely on purpose. `Email <> EmailAddress` alone is NOT enough: when either
-- side is NULL the comparison yields UNKNOWN, not TRUE, so a plain inequality silently
-- misses the new-only writer (Email set, EmailAddress left NULL) — which is exactly the
-- divergence this check exists to catch.
SELECT COUNT(*) FROM dbo.Users
WHERE EXISTS (SELECT Email EXCEPT SELECT EmailAddress);
```

Run these repeatedly over a period that covers your slowest job. A single zero proves the
backfill finished; a *sustained* zero proves the dual-write is genuinely universal.

### `NULL` is ambiguous — resolve it

`Email IS NULL` means either "the user has no email" or "not backfilled yet". Distinguish
them with the old column:

| `EmailAddress` | `Email` | Meaning |
|---|---|---|
| `NULL` | `NULL` | legitimately no email |
| non-null | `NULL` | **not yet backfilled** — must reach 0 |
| non-null | non-null | migrated |
| `NULL` | non-null | **a new-only writer** — some path writes `Email` and skips `EmailAddress`. Phase 2 is incomplete; the legacy host cannot see this user's email at all. |

The first three rows are the ones people look for. The fourth is the one that bites: it means
the dual-write is not universal, and because the legacy host is still authoritative for reads
elsewhere, the data is *invisible* to it rather than merely stale. Both the middle rows must
reach 0 before Phase 5. Do not enforce `NOT NULL` on `Email` if the first row legitimately
exists.

## Phase 5 — Read switch

Read the new column, fall back to the old. Deploy, then soak.

```csharp
var email = user.Email ?? user.EmailAddress;
```

The fallback is what makes this deployment reversible: if it is rolled back, the previous
revision reads `EmailAddress`, which is still being written. **Keep the fallback until Phase 7.**
Phase 6 does not make it redundant — it adds a *filtered* unique index, which by design still
permits `Email` to be `NULL`, so a row can legitimately reach the read path with no new value.
The fallback is removed in Phase 7, in the same deployment that stops the old write, and it
must ship before the `DROP COLUMN`.

## Phase 6 — Enforce

Only after the read switch has soaked. Add the constraint — and **keep dual-writing**.

Stopping the `EmailAddress` write here is the intuitive move, and it is wrong. Phase 7's
inventory below exists because reports, jobs and BI extracts routinely outlive the web host;
every one of them still reading `EmailAddress` goes silently stale the moment that write stops.
Enforcement does not require it. Retiring the old write is a *contraction* step, so it moves to
Phase 7 behind the same retirement gate as the column drop.

```sql
-- Uniqueness is a NEW business rule, not part of the rename. Dual-write copies
-- EmailAddress verbatim, and EmailAddress was never unique -- so any duplicate that
-- already existed has been faithfully mirrored into Email. Confirm this returns no
-- rows before creating the index; otherwise the CREATE fails.
SELECT Email FROM dbo.Users
WHERE Email IS NOT NULL
GROUP BY Email HAVING COUNT(*) > 1;

-- Filtered: SQL Server allows only ONE NULL in a standard unique index,
-- so a plain UNIQUE index breaks every user without an email.
CREATE UNIQUE NONCLUSTERED INDEX UX_Users_Email
    ON dbo.Users (Email)
    WHERE Email IS NOT NULL
    WITH (ONLINE = ON);
```

Three things matter here:

- **The duplicate precheck** — dual-write makes the *column* safe to enforce on; it does not
  make the *data* unique. Nothing in Phases 1–5 deduplicates, because nothing in a rename
  should. If the query returns rows, reconciling them is a product decision, not a schema
  step — take it to the owning team before going further.
- **`WHERE Email IS NOT NULL`** — without the filter, the second user with a NULL email
  violates the index.
- **`ONLINE = ON`** — an offline build holds a table lock for its duration, which stalls
  *both* hosts. `ONLINE = ON` requires Enterprise or Azure SQL. On Standard there is no online
  path, so defer the index to Phase 7 rather than dropping the option and building it offline
  while both hosts are live. If you need the constraint enforced sooner than that, an offline
  build in an agreed maintenance window is the only remaining route — treat it as planned
  downtime for both hosts, not as a variant of this phase.

Note that this index could not have been created in Phase 1 — while the legacy host was still
writing `EmailAddress` only, every row's `Email` was `NULL`, so a filtered index would have had
nothing to enforce and an unfiltered one would have collapsed on the second row. Reaching
Phase 6 removes *that* obstacle. It does not remove duplicate values, which is why the
precheck above is not optional.

## Phase 7 — Contract

**Not while any old consumer remains.** Before dropping, confirm the retirement of:

- the Framework web host
- every background job and scheduled task
- reports, dashboards, and BI extracts reading `EmailAddress`
- any rollback artifact you might still deploy — if a previous revision reads the old column,
  dropping it makes that rollback impossible
- external integrations, ETL, and downstream replicas

Retiring the web host is **not** sufficient. Reports and jobs outlive it routinely.

Remove the `EmailAddress` write, the Phase 5 read fallback, **and the `EmailAddress` property
from both models** — then deploy that, and only then run the `DROP`.

The model property is the part that is easy to miss and the most damaging to get wrong. Both
EF6 and EF Core emit every mapped scalar in their `SELECT` lists, so a model that still maps
`EmailAddress` against a table that no longer has it fails *every read of that entity* with
`Invalid column name 'EmailAddress'` — not just the code paths that touch the property.
Dropping the column while the property is still mapped takes the application down.

Until this deployment the dual-write has been carrying every consumer you had not yet
inventoried; stopping it is what makes the inventory above load-bearing rather than advisory.

```sql
-- Only after every consumer above is confirmed retired, AND the deployment
-- that unmapped the property has soaked
ALTER TABLE dbo.Users DROP COLUMN EmailAddress;
```

## Summary

| Phase | Change | Reversible? | Gate to proceed |
|---|---|---|---|
| 1 | add nullable column | yes | both hosts healthy |
| 2 | dual-write everywhere | yes | **every** writer deployed |
| 3 | backfill | yes | batches complete |
| 4 | verify | n/a | both counts sustained at 0 |
| 5 | read new, fall back | yes | soaked; error rate flat |
| 6 | filtered unique index; **dual-write continues** | yes | reads confirmed on new column |
| 7 | stop old writes; unmap property; drop old column | **no** | every consumer retired |

Phases 1–6 are all reversible by rolling code back (and, for Phase 6, dropping the index); the
schema only ever moves forward. Phase 7 is the only irreversible step, and it is irreversible
in two ways — stopping the old write strands any consumer you missed just as permanently as
dropping the column does. That is why its gate is a retirement inventory rather than a soak
period.
