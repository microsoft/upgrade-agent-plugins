---
name: managing-shared-database-schema
description: >
  Governs a SQL database that two hosts read and write at the same time during a side-by-side
  migration. Use when a legacy .NET Framework app and a new .NET app share one database, point
  at the same connection string, or must both stay live while the schema changes. Covers which
  toolchain owns schema changes, expand-then-contract (additive-only) evolution, dual-write and
  backfill ordering, deployment ordering, and rollback rules. Triggers for "shared database",
  "who runs migrations", "dual write", "zero downtime schema change", or "add a column safely".
  Applies to EF6, EF Core, Dapper, ADO.NET, DACPAC/SqlPackage, DbUp and Flyway, and explains how
  EF6's __MigrationHistory and EF Core's __EFMigrationsHistory coexist without merging. Also use
  before deleting a Migrations folder, before enabling Database.Migrate() at startup, or when
  asked whether renaming or dropping a column is safe while the old app is live.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Managing a Shared Database During Side-by-Side Operation

## Overview

In a side-by-side migration, the legacy .NET Framework host and the new .NET host both run
against **one SQL database** for weeks or months. Every schema change in that window must be
tolerated by code that is still running and by code that is being deployed — simultaneously.

This skill is **ORM-agnostic**. The rules apply equally to EF6, EF Core, Dapper, raw ADO.NET,
and SQL-first tooling. Where a rule needs a concrete binding, the EF6 and EF Core forms are
given side by side.

> **Read `ref/worked-example.md` before making any schema change.** It carries the full
> column-rename walkthrough with the exact ordering. The phase skeleton below is a summary,
> not a substitute.

## Scope

**In scope:** one database, two or more live application hosts, a bounded migration window.

**Out of scope:** ETL and data warehousing, database-per-service decomposition, read replicas
and sharding, cross-database distributed transactions.

**Related skills:**
- `migrating-ef6-code-first-to-ef-core` — the EF6→EF Core code migration. Its teardown steps
  are for **full cutover only** and must not run while both hosts are live.
- `migrating-ef-dbcontext` — DbContext registration and DI. Its startup-migration sample is
  gated on the ownership decision made here.
- `migrating-aspnet-framework-to-core` — the side-by-side task structure that creates this
  window.

## Window admission checklist

Do not open the shared-database window until all five hold:

- [ ] **Schema-writer inventory exists** (Step 1 below) and is written into `task.md`
- [ ] **Actual schema matches the model** — no undeployed pending migrations on either side
- [ ] **Startup migration is disabled on both hosts** — no `Database.Migrate()` in `Program.cs`,
      no `MigrateDatabaseToLatestVersion` initializer, no `EnsureCreated()`
- [ ] **Backup / point-in-time restore verified** — tested, not merely configured
- [ ] **DDL permissions restricted** to the single runner identity; application logins hold
      DML only (`db_datareader` + `db_datawriter`, not `db_ddladmin`/`db_owner`)

If any check fails, fix it before proceeding. Opening the window with two hosts able to issue
DDL is the failure mode this skill exists to prevent.

## Step 1: Schema-writer inventory

Produce a **written table in `task.md`**. Do not proceed on recollection or assumption.

Search the whole solution — both hosts, and any jobs, tools or deployment scripts:

| What to search for | Indicates |
|---|---|
| `DbMigrator`, `migrate.exe`, `Update-Database` | EF6 migration runner |
| `Database.Migrate()`, `dotnet ef database update` | EF Core migration runner |
| `EnsureCreated()`, `CreateDatabaseIfNotExists`, `DropCreateDatabase*` | implicit schema creation |
| `SqlPackage`, `.sqlproj`, `.dacpac` | SQL-first deployment |
| `DbUp`, `Flyway`, `Liquibase`, `RoundhousE` | third-party migrator |
| `CREATE TABLE`, `ALTER TABLE` in `.sql` files or embedded strings | ad-hoc DDL |
| connection-string names shared across `*.config` and `appsettings*.json` | the shared database itself |

Record one row per finding, each citing `path:line`:

| Writer | Toolchain | Where it runs | Evidence |
|---|---|---|---|
| `MyApp.MigrationRunner` | EF6 `DbMigrator` | scheduled job | `src/Jobs/Migrate.cs:42` |

**Do not select an ownership case until the table has at least one evidenced row**, or an
explicit "none found — asked the user and they confirmed X".

## Step 2: Decide who owns schema changes

This is a **procedure**, not a lookup. Follow it in order.

1. Build the inventory (Step 1).
2. **If more than one DDL-capable writer type appears — stop and ask the user who owns the
   pen.** Do not infer it. Two writers with two ledgers is the root cause of nearly every
   failure in this window.
3. If exactly one appears — that is **Case A**. Still enforce a single deployable runner.
4. Choose **Case C** only when the user confirms SQL-first ownership, or when the window is
   long enough that neither ORM should hold the pen.

Record the decision and its rationale in `task.md`. Every later step depends on it.

### Case A — one toolchain, one runner *(most common)*

Both web hosts are inert with respect to schema. One deployable migrator applies changes.

- No startup migration in either host.
- One runner, one place, one schedule.
- **Concurrency is the residual risk.** EF6's `DbMigrator` takes **no** distributed lock.
  EF Core 9+ *does* take one (`__EFMigrationsLock`) — but the two **do not coordinate with
  each other**. Two concurrent runners can interleave DDL.
- **They can be made to coordinate.** On SQL Server, EF Core's lock is an `sp_getapplock`
  taken on the resource name `__EFMigrationsLock`. A non-EF-Core runner that takes an
  exclusive `sp_getapplock` on that *same* resource name therefore serializes against
  `dotnet ef database update` as well as against itself. This is an EF Core implementation
  detail, not a documented contract — confirm it for your EF Core version before relying on
  it, and keep "one runner" as the primary control rather than the lock.
- Serialize explicitly. Either run migrations from a single scheduled job that cannot overlap
  itself, or wrap the runner in an application lock:

```sql
DECLARE @lock int;
EXEC @lock = sp_getapplock @Resource = 'schema-migration', @LockMode = 'Exclusive',
                           @LockOwner = 'Session', @LockTimeout = 60000;
IF @lock < 0
    THROW 50000, 'Could not acquire the schema-migration lock; another runner holds it.', 1;

-- run the migrations now, then release. The migration may open its own
-- connection; this one only has to stay open for the whole run to hold the lock.

EXEC sp_releaseapplock @Resource = 'schema-migration', @LockOwner = 'Session';
```

Two details decide whether this actually protects anything:

- **Check the return value.** `sp_getapplock` does *not* raise an error on failure — it
  returns a negative value (`-1` timeout, `-2` cancelled, `-3` deadlock victim, `-999` argument
  error). An `EXEC` whose result nobody inspects therefore **fails open**: the timeout elapses,
  the batch continues, and the migration runs with no lock at all — precisely the case this is
  meant to prevent.
- **`@LockOwner = 'Session'` binds the lock to the connection that took it**, and that
  connection must stay open for the whole run. The migration itself may execute on a different
  connection — the lock provides mutual exclusion between *runners*, not between connections —
  which is what makes this usable with EF6's `DbMigrator`, since it opens its own connection.
  What breaks the guarantee is closing the lock-holding connection early, or a runner that
  deploys without taking the lock at all. Use `@LockOwner = 'Transaction'` only if the
  migration genuinely runs inside that transaction.

### Case B — two toolchains, one holds the pen

**Default: EF6 keeps the pen** for the duration of the window.

Two reasons, both concrete:

- **Convention drift.** EF6 names constraints `FK_dbo.Posts_dbo.Blogs_BlogId`; EF Core names
  them `FK_Posts_Blogs_BlogId`. EF Core scaffolds a migration by diffing its model against
  **its own snapshot, never against the live database**, so it cannot see those legacy names.
  An unbaselined first migration therefore emits `CREATE` for the entire model — every object
  it "creates" already exists — and once baselined, subsequent migrations emit `ALTER`/`DROP`
  against EF Core-convention names that are not what the database actually calls them.
- **Variable isolation.** Moving schema deployment from `DbMigrator`/`migrate.exe` to
  `dotnet ef` *during* the window conflates an infrastructure migration with an application
  migration, on the host still serving production traffic.

**When to override the default.** Hand the pen to EF Core instead only when all three hold —
and record the reason in `task.md`:

1. The Framework host is **feature-frozen**: kept alive to serve traffic, not developed
   against. Authoring every schema change in a codebase no one is working in is real friction,
   and this is the case the default gets wrong.
2. EF Core's **model** has been reverse-engineered from the live database with
   `Scaffold-DbContext`, so it already carries the legacy constraint names (see the bootstrap
   rule below). This is a *model* bootstrap and nothing more: `Scaffold-DbContext` produces
   entity classes and a `DbContext`. It creates no migration, no `ModelSnapshot.cs` and no
   `__EFMigrationsHistory` row, so it does **not** baseline the ledger.
3. The switch happens **once, at a planned checkpoint** — never per change — and the Step 3
   handover procedure (scaffold the baseline, review it, register it with the history-table
   script) completes **within that same checkpoint**. EF Core must not own the pen for even
   one change while its ledger is still empty: its first `migrations add` would diff against
   an empty snapshot and emit `CreateTable` for the entire model.

If any of the three fails, EF6 keeps the pen. Either way the handover is a one-time event:
alternating writers is prohibited (Step 3).

Rules:
- The non-owner **never scaffolds a migration**. It models the schema read-only.
- If EF Core must eventually take the pen, bootstrap it with `Scaffold-DbContext` against the
  live database. That emits explicit `HasConstraintName(...)` calls pinning EF Core to the
  legacy names, neutralising the convention diff. It does **not** register a ledger baseline —
  that is Step 3's handover procedure, and both are required before EF Core owns the pen.
- **Pin delete behaviour explicitly — "we emit no DDL" does not make it moot.** `DeleteBehavior`
  governs two separate things: the FK clause EF Core would write *in a migration*, and what EF
  Core does *at runtime* to dependents it has loaded. The non-owner emits no migration, so the
  first is irrelevant — which is precisely why it gets skipped, and why the second then bites. A
  required (non-nullable) FK defaults to `DeleteBehavior.Cascade`, so deleting a principal makes
  EF Core issue `DELETE` for each tracked child. Against a live FK declared `NO ACTION` those
  child deletes are perfectly legal and succeed, so the rows vanish — while the EF6 host doing
  the same delete gets an FK violation. One database, two behaviours, and no error anywhere to
  reveal it. Mirror the live constraint: `WillCascadeOnDelete(false)` or `NO ACTION` means
  `.OnDelete(DeleteBehavior.Restrict)`. Read the real FK; never accept the convention default.

### Case C — neither ORM owns; SQL-first

Both ORMs are frozen as read-projections of a schema owned by DACPAC/SqlPackage, DbUp or
similar. That system carries its own authoritative ledger. Neither `Add-Migration` nor
`dotnet ef migrations add` is run at all.

## Step 3: Migration ledgers coexist — they never merge

EF6 and EF Core write **different tables**:

| | EF6 | EF Core |
|---|---|---|
| Table | `dbo.__MigrationHistory` | `dbo.__EFMigrationsHistory` |
| Model snapshot | gzipped EDMX in the `Model` column | `<DbContext>ModelSnapshot.cs` in source |

They never collide — which is **worse** than colliding. Each runner scaffolds its next
migration by diffing against *its own* snapshot, so EF6's `Add-Migration` happily re-adds a
column EF Core already created, and vice versa.

Rules:

- **Never** point EF Core at EF6's history table.
- **Never** copy rows between the two tables. The formats are not interchangeable.
- Preserve EF6's ledger **read-only** — the Framework host still needs it.
- **Handover** (at the moment EF Core takes ownership of schema deployment — by default at
  cutover, and during the window only under the Step 2 override): scaffold an EF Core baseline
  migration. It **will contain the full `CreateTable` set for the whole model** — a first
  migration diffs against an empty snapshot, so an empty `Up()` is not something you can wait
  for, and an instruction to "verify it contains no operations" can never be satisfied. Review
  it to confirm it describes the schema that *already exists*, then register it **without
  executing it**: generate `dotnet ef migrations script --idempotent` and apply only its
  history-table parts — the conditional `CREATE TABLE __EFMigrationsHistory` block (an
  EF6-only database has no such table, so the insert alone fails) and the
  `INSERT INTO __EFMigrationsHistory` row. Do **not** use `dotnet ef database update` — that
  command *executes* the migration; EF Core has no `--fake`.
- Where several `DbContext` types share one database, each has its own history rows. Decide
  behaviour per context, not per database.
- Changing owner requires a **fresh baseline checkpoint**. Alternating writers is prohibited.

> **Precondition:** the EF6 host must call `Database.SetInitializer<MyContext>(null)`.
> An app that keeps `MigrateDatabaseToLatestVersion` runs `DbMigrator.Update()` on first
> context use, which **applies any pending EF6 migration automatically at startup** — a second
> uncoordinated schema writer that deploys on process start rather than on your schedule.
> Nulling the initializer also bypasses the model-compatibility check
> (`Database.CompatibleWithModel`), which the initializer pipeline invokes. Be clear about what
> that check does *not* do: it compares the current model against the model hash stored in
> `__MigrationHistory`, so it reacts to **your code** changing, not to the physical schema
> advancing underneath it. Additive DDL applied out of band does not trip it.
>
> With the initializer nulled, EF6 **silently tolerates** added columns and tables, because it
> emits explicit column lists rather than `SELECT *`. It fails only when a column it *knows
> about* is dropped or renamed, or when a `NOT NULL` column without a default is added and EF6
> inserts a row.

## Step 4: Expand-then-contract — additive only

**Inside the window, schema changes are additive only.** Contraction happens after the legacy
host is retired.

**Prohibited while both hosts are live:**

| Change | Why it breaks |
|---|---|
| Rename a column or table | legacy host's explicit column list stops resolving |
| Drop a column or table | same, immediately |
| Narrow a type (`nvarchar(200)`→`(50)`, `bigint`→`int`) | legacy writes overflow |
| Change a primary key or clustered index | rewrites the table; blocks both hosts |
| **Add a UNIQUE constraint or unique index** *on a column a host already writes* | the legacy host keeps writing duplicates |
| **Create a non-clustered index without `ONLINE = ON`** | takes a lock for the build's duration |
| Add `NOT NULL` without a default | legacy `INSERT` omits the column and fails |

The unique-index row applies to columns that are **already being written**. A *new* column is
the different case: once the Step 5 dual-write is deployed to every writer, they all populate
it, so a **filtered** unique index becomes legal at the Enforce phase — see Step 5 phase 6 and
`ref/worked-example.md` Phase 6, which shows why the same index is illegal at expand time.

**Adding a `NOT NULL` column with a default is metadata-only — and therefore safe — only when
all four hold:**

1. **SQL Server 2012 or later, Enterprise edition** (Evaluation, and Developer on 2022 and
   earlier, are Enterprise-equivalent; **SQL Server 2025 Standard Developer is not** — that
   release splits Developer into Enterprise Developer and Standard Developer, and the latter
   carries Standard's limits), or Azure SQL. On **Standard this is a full table rewrite under a
   `Sch-M` lock** regardless of everything below — the most common way this step goes wrong is
   assuming otherwise. Validating on a Standard Developer box and concluding production will
   behave the same way is the version of that mistake this note exists to prevent.
2. The default is a **runtime constant** — an expression producing the same value for every
   row, such as `0`, `''`, or `GETDATE()`. **Not** `NEWID()` or `NEWSEQUENTIALID()`, and not a
   scalar UDF; those force a full rewrite.
3. The column's type is **not** `varchar(max)`, `nvarchar(max)`, `varbinary(max)`, `xml`,
   `text`, `ntext`, `image`, `hierarchyid`, `geometry`, `geography`, or a CLR UDT. These are
   excluded from the online path outright, independently of the other conditions.
4. Adding it does not push the table's **maximum possible row size** past 8,060 bytes.

If any fail, treat it as a rewrite: add the column nullable, backfill in batches, then enforce.

**Safe — but only under these conditions:**

| Change | Condition |
|---|---|
| Add a nullable column | unconditional |
| Add a new table | unconditional |
| Add a default constraint | unconditional — it does not touch existing rows |
| Add a non-clustered index `ONLINE = ON` | **Enterprise or Azure SQL only.** Still takes a short lock at the start and a `Sch-M` lock to finish, and needs log and `tempdb` headroom. On Standard there is no online path, so defer the index to contraction. |
| Widen a type | only when the widening is genuinely metadata-only. `varchar(50)`→`varchar(100)` is; **`int`→`bigint` and `varchar`→`nvarchar` rewrite the whole table.** `int`→`bigint` is also an *application* break: as soon as the new host writes a value beyond `Int32`, the legacy host's mapping overflows reading it back. |

## Step 5: Phase skeleton

Every non-trivial change follows this order. **Ordering is not stylistic — inverting steps 2
and 3 loses data.**

1. **Expand** — add the new nullable column/table. Deploy alone.
2. **Dual-write** — deploy to **every** writer, so new writes populate old *and* new.
3. **Backfill** — batched, restartable, race-safe; only rows the dual-write did not cover.
4. **Verify** — old and new agree continuously; no unmigrated writer remains.
5. **Read switch** — read new, fall back to old. Deploy. Soak.
6. **Enforce** — add the final constraint (a filtered unique index, or `NOT NULL` where the
   value is genuinely mandatory). Keep dual-writing: enforcement does not require the old
   write to stop, and stopping it early strands every old reader you have not yet retired.
7. **Contract** — stop the old write *and* drop the old column, **only** after every old
   consumer is retired. These belong together: from the moment old writes stop, any surviving
   reader of the old column is silently reading stale data, and a rollback to a pre-dual-write
   revision can no longer be trusted.

Backfilling before the dual-write is deployed loses every row written between the two — this
is the single most common way to corrupt data in this window. See `ref/worked-example.md`.

## Step 6: Deployment ordering

Schema first, always. Every schema change must be independently deployable and must not
require a simultaneous code deployment.

Per change:

| PR | Contains | Done when |
|---|---|---|
| PR1 | DDL only | new column exists; both hosts still healthy |
| PR2 | dual-write in every writer | new column populated on every new write |
| PR3 | backfill job | `COUNT(*) WHERE new IS NULL AND old IS NOT NULL` = 0 |
| PR4 | read switch | new path serving reads; error rate flat |
| PR5 | constraint DDL only | constraint enforced; dual-write still running |
| PR6 | contract (post-retirement): stop the old write, drop the read fallback, **unmap the property from every model** | deployed and soaked, **before** any `DROP` |
| PR7 | contract DDL | old column dropped |

PR6 and PR7 are separate deployments on purpose: dropping the column in the same unit that
stops writing it leaves no window in which to discover a consumer the retirement inventory
missed. Unmapping the property belongs in PR6 for a harder reason — EF emits every mapped
scalar in its `SELECT` list, so a model still mapping a dropped column fails *every* read of
that entity, not only the paths that use it.

Never combine DDL and application logic in one deployable unit.

## Step 7: Rollback contract

**Invariant: every schema state must be tolerated by all four of** {old Framework code, new
Framework code, old Core code, new Core code}.

- **Code rolls back. Schema does not.** A rolled-back deployment must run against the
  *advanced* schema — which is exactly what additive-only guarantees.
- **Down-migrations are banned in the window.** `Down()` methods are not tested against live
  data and typically drop columns the other host is still reading.
- **Recovery = roll forward.** If a schema change is wrong, deploy a **compensating additive
  migration**, or perform a controlled manual DBA intervention with a verified backup — never
  an automated `Down()`.

## Step 8: Runtime safety across two stacks

One schema, two ORMs, different conventions. Check each:

- **Concurrency tokens.** A `rowversion`/`timestamp` column must be mapped as a concurrency
  token in **both** stacks (EF6 `[Timestamp]` / `IsRowVersion()`; EF Core `IsRowVersion()`),
  or one host silently overwrites the other's changes.
- **Convention drift against one schema:**
  - `decimal` — EF6 defaults to `decimal(18,2)`; EF Core requires explicit `HasPrecision`.
    Mismatch silently truncates.
  - `string` — EF6 defaults to `nvarchar(max)`/Unicode; confirm EF Core's `HasMaxLength`
    and `IsUnicode` match the actual column.
  - `DateTime` — `datetime` vs `datetime2` precision differs; round-tripping can shift values.
  - **Cascade deletes** — EF6 and EF Core default differently, and the non-owner emitting no
    DDL does **not** make this cosmetic: the default still drives runtime deletes. See Case B.
  - **Index and FK naming** — see Case B.
- **Transactions.** `TransactionScope` with MSDTC promotion has limited support on
  `Microsoft.Data.SqlClient` / modern .NET. Prefer a single local transaction per operation;
  where cross-resource atomicity is genuinely needed, use an outbox.
- **Cache invalidation.** Each host has its own in-memory cache. A write by one is invisible
  to the other's cache. Shorten TTLs, or use a shared/distributed cache, for data both mutate.
- **Drift fingerprint.** Before each advance, re-check the live schema against both models —
  the window is long enough for out-of-band changes to appear.

## Step 9: Detection and gating

Apply this skill when **either** holds:

- `Upgrade Options > Project Structure > Project Approach` is **Side-by-side**, **or**
- the schema-writer inventory shows two or more hosts on one connection string.

**Standalone fallback** — no upgrade options available: treat as shared if two projects
resolve the same server+database, or if a connection string name is duplicated across a
`*.config` and an `appsettings*.json`.

**Fail closed.** If the connection strings are tokenized, injected at deploy time, or pulled
from Key Vault so sharing cannot be proven — **ask the user**. Do not assume they are separate.

## Decomposition Rules

*(Read by the task-breaker when this skill is attached to a task being decomposed. This exact
heading is the one both `task-breaker` and `task-executor` scan for — do not rename it.)*

**Restate the pin on every data-touching subtask.** A subtask's `task.md` is written from the
breakdown alone — it is not merged with its parent — so a `#skill:` pin in the parent
description does not reach the child. When breaking down a task that carries
`#skill:managing-shared-database-schema`, copy that pin verbatim into the description of every
subtask whose scope includes a `DbContext`, an entity model, a connection string, a migration,
a repository, or raw SQL. Without it the subtask that actually writes the schema is the one
agent in the run that cannot see this skill.

**Do not create a subtask that performs a contraction.** Rename-column, drop-column,
narrow-type, add-unique-constraint and "clean up the old column" are not valid subtasks inside
the window, no matter how naturally they fall out of the parent's scope. If the parent's work
implies one, split it into an expand subtask now and a contraction item recorded for after the
Framework host is retired.

**Sequence dual-write before backfill.** If the breakdown produces both, the dual-write subtask
must be ordered first and marked as a dependency of the backfill subtask. Reversing them loses
every row written between the two deployments.

## Success criteria

- Schema-writer inventory written to `task.md`, every row citing `path:line`
- Exactly one schema owner chosen, recorded, and justified
- No `Database.Migrate()`, `EnsureCreated()`, or migration-applying initializer in either host
- EF6 `Migrations/` folder and `Configuration` class **intact** if EF6 owns the pen
- The two migration ledgers untouched by each other — no merging, no row copying
- Every schema change in the window additive-only
- Dual-write deployed **before** any backfill runs
- No contraction DDL while any old consumer remains
- Rollback verified: previous code revision runs against the advanced schema
