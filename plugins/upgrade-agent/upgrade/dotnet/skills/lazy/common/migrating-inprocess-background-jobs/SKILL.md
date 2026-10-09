---
name: migrating-inprocess-background-jobs
description: >
  Ports background jobs from ASP.NET Framework to ASP.NET Core and the .NET Generic Host, and stops a
  job running twice while the legacy and new hosts are both live. Use when an app uses WebBackgrounder
  (JobManager, IJob, IJobCoordinator, WebFarmJobCoordinator), HostingEnvironment.QueueBackgroundWorkItem,
  IRegisteredObject or HostingEnvironment.RegisterObject, timers or Task.Run loops started from
  Application_Start, WebActivatorEx or OWIN Startup, or console job runners whose Main loops and sleeps
  or runs once per external trigger. Covers BackgroundService, IHostedService, Channel<T> work queues, Generic Host and Worker
  Service console jobs, shutdown and failure behaviour, and a duplicate-execution guard for side-by-side
  migration: a shared SQL schedule row or an Azure blob lease that both hosts take, fencing tokens, and
  handover. Triggers for "background job", "scheduled job", "hosted service", "job runs twice", "double
  fire", "leader election", "distributed lock", or "singleton job".
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Migrating In-Process Background Jobs

## Overview

ASP.NET Framework apps run background work in three shapes, and none of them survives the move to
ASP.NET Core unchanged:

1. **WebBackgrounder** — `JobManager` running `IJob` instances on a timer inside the web app.
2. **`HostingEnvironment.QueueBackgroundWorkItem`** (QBWI) and `IRegisteredObject` — work the ASP.NET
   runtime tracks so shutdown can wait for it.
3. **Console job runners** — a `Main` that loops, sleeps, and exits with a code, run by an external
   scheduler or left running.

Porting the code is the smaller problem. During a side-by-side migration the Framework host and the
Core host are **both live**, so a job ported to Core while it still runs in Framework executes twice.
For a cache refresh that is harmless. For a job that sends mail, deletes rows, or charges a card, it is a
data-integrity incident. Step 6 is the part of this skill that prevents it.

## Scope

**In scope:** jobs hosted inside an ASP.NET Framework web app, QBWI and `IRegisteredObject` work, and
console job executables, moved to ASP.NET Core or the Generic Host — including while both hosts run.

**Out of scope — keep the existing scheduler:** Hangfire, Quartz.NET, the Azure WebJobs SDK, and Azure
Functions timer triggers **can** coordinate across hosts, but only when configured to. Do not replace them
with a hand-written `BackgroundService`; port them with their own migration guidance. Do not assume they
are safe, either: verify that both hosts use persistent (not in-memory) storage, the same storage, a
schema version both package versions accept, clustering or singleton settings that are actually enabled,
stable scheduler and job identifiers, and retry semantics the jobs tolerate. Anything unverified makes
each host schedule its own copy, and Step 6 applies.

**Related skills:**
- `managing-shared-database-schema` — governs the schedule table this skill adds (Step 6).
- `migrating-global-asax` — `Application_Start` and `Application_End`, where many jobs are started.
- `migrating-aspnet-framework-to-core` — the side-by-side task structure that creates the window.
- `migrating-mvc-dependency-injection` — resolving job dependencies from the new container.

## Step 1: Inventory every job

Produce a **written table in `task.md`**. Search the web project, its class libraries, and every console
project and deployment script:

| Search for | Indicates |
|---|---|
| `WebBackgrounder`, `JobManager`, `: Job`, `IJob`, `IJobCoordinator`, `WebFarmJobCoordinator` | WebBackgrounder |
| `QueueBackgroundWorkItem` | QBWI |
| `IRegisteredObject`, `HostingEnvironment.RegisterObject` | shutdown-aware background work |
| `new Timer(`, `System.Timers.Timer`, `Task.Run(`, `new Thread(`, `ThreadPool.QueueUserWorkItem` in startup code | hand-rolled job |
| `Application_Start`, `PreApplicationStartMethod`, `PostApplicationStartMethod`, `ApplicationShutdownMethod`, OWIN `Configuration(IAppBuilder)` | where jobs are started and stopped |
| `static void Main` / `static async Task Main` with a loop and `Thread.Sleep` or `Task.Delay` | continuous console job |
| `settings.job`, `App_Data/jobs/`, Task Scheduler XML, cron entries, container job definitions | how a console job is scheduled |
| `Hangfire`, `Quartz`, `Microsoft.Azure.WebJobs` | existing scheduler — see Scope |

Record one row per job, each citing `path:line`:

| Job | Pattern | Runs in | Trigger and cadence | State it changes | Current coordination | Evidence |
|---|---|---|---|---|---|---|
| `ExpireStaleRecords` | WebBackgrounder | web host, every instance | every 60 min after the previous run | deletes rows in the app database | none | `src/Web/Jobs.cs:42` |

"State it changes" decides everything after this step. Read the job body; do not infer it from the name.

## Step 2: Classify each job

Answer four questions per job and add the answers to the inventory:

| Question | Answers | Decides |
|---|---|---|
| What does a run change? | process-local state only, shared state, or both | how many copies may run |
| How many copies may run one occurrence? | every instance, or one executor across all hosts | whether Step 6 applies |
| What if an occurrence is lost or repeated? | loss is acceptable, or it must eventually run once its effects are idempotent | delivery guarantee |
| What triggers it? | timer, startup, request, queue, or an external scheduler | the port target (Steps 3–5) |

Apply these rules:

- **Process-local only** — an in-memory cache, a warm-up — runs in **every instance of both hosts**, with
  no guard. Gating it on a shared lock leaves every non-holder serving a stale cache.
- **Machine-local files** — a local index, a disk cache — are shared by every process on that machine.
  When both hosts, or two IIS worker processes, run on one machine, give each its own path or make one
  of them the only writer there.
- **Any shared write** — database, blob, queue, mail, external API, cleanup or deletion — needs a
  **single executor per occurrence** across all hosts and instances. Step 6 is mandatory for it.
- **Both** — split it into a per-instance refresh and a single-executor job. A write keyed by host
  (a heartbeat row per instance) is per-instance; make it an idempotent upsert on the host key.
- **Request-triggered** work runs on the host that served the request. Classify its delivery:
  best effort (an in-memory queue is fine), must eventually complete (durable queue or outbox), or must
  complete before the response (keep it in the request).
- **Cannot tell whether a write is shared** — treat it as shared.

A worked inventory and classification of a real application, including which of its jobs must **not**
be guarded: [ref/worked-example.md](ref/worked-example.md).

## Step 3: Port WebBackgrounder jobs

WebBackgrounder depends on `System.Web` — its `JobHost` registers with `HostingEnvironment` — so it cannot
be referenced from ASP.NET Core. Rewrite each job as a `BackgroundService`, preserving these behaviours:

| WebBackgrounder behaviour | What the port must do |
|---|---|
| `Execute()` often returns an **unstarted** `new Task(...)`; `JobHost` starts it | Never `await job.Execute()` on legacy code — an unstarted task never completes. Rewrite the body as `async Task RunAsync(CancellationToken)`. |
| `new Task(async () => ...)` is an `async void` lambda: the task completes at the first `await` | The real work was untracked and its exceptions escaped the scheduler. Await the work directly in the port. |
| `Start()` runs the **shortest-interval** job of each `JobManager` straight away; the others first run one interval later; after that each interval runs from the **end** of the previous run | Run first, then delay, for the job that ran at `Start()` — a delay-first loop leaves its cache cold after every restart. Delay first for the others, unless the legacy code also ran them at startup through a QBWI call or a constructor. Delay after each run. |
| One `JobManager` runs all its jobs **serially** on one timer | Separate services run concurrently. Keep jobs in one service only if they share state that is not thread-safe. |
| `Fail(...)` with `RestartSchedulerOnFailure = true`, or a coordinator that logs and swallows | A failed run was logged and the schedule continued. Keep that policy explicitly — see Step 7. |
| `RestartSchedulerOnFailure` left at its default, `false`, with a coordinator that lets faults through | One faulted run stopped the `JobManager`'s timer for good: every job in it stopped until the next recycle. Do not reproduce that. When adding the guard to the Framework copy, set `RestartSchedulerOnFailure = true` with a logging `Fail(...)` handler first — a claim surfaces store errors and lost claims as faults. |
| `SingleServerJobCoordinator`, or a custom coordinator that calls `Execute()` | No cross-instance coordination existed: every instance already ran the job. |
| `WebFarmJobCoordinator` with a `WorkItems` table | A cross-instance **mutex**, not once-per-interval: N servers each run it once per interval, without overlapping. See Step 6. |
| `Timeout` | Only expires a `WorkItems` reservation. It never cancelled a run. |

Code for the port, including a scope per run: [ref/porting-patterns.md](ref/porting-patterns.md).

## Step 4: Port QueueBackgroundWorkItem and IRegisteredObject

| Legacy shape | Port to |
|---|---|
| QBWI from startup, often a `while (!token.IsCancellationRequested)` refresh loop | a `BackgroundService` |
| QBWI from a request, best effort | a bounded `Channel<T>` drained by a `BackgroundService`, with a DI scope per item |
| QBWI from a request whose work must eventually complete | a durable queue or an outbox table, drained by a single-executor job |
| One-off, loss-tolerant work with nothing to drain | `Task.Run` under `ExecutionContext.SuppressFlow()`, with its exception observed and `IHostApplicationLifetime.ApplicationStopping` as its token |
| `IRegisteredObject.Stop(bool immediate)` | `IHostedService.StopAsync`, or `ApplicationStopping` |

Semantics that change:

- ASP.NET tracks QBWI items and tries to delay AppDomain shutdown until they finish. The Generic Host
  waits only for hosted services' `StopAsync`, up to `HostOptions.ShutdownTimeout` (30 seconds by
  default). `Task.Run` work is **not** waited for, and an in-memory `Channel<T>` loses whatever is queued
  when the process stops. Neither is a substitute for durable delivery.
- QBWI does not flow `ExecutionContext`. Neither should the port: capture the values the work needs
  when it is queued. Never capture `HttpContext` or a scoped service — both are gone once the response
  completes.
- Bound every queue and decide what happens when it is full: wait, drop, or fail the request.

Code: [ref/porting-patterns.md](ref/porting-patterns.md).

## Step 5: Port console jobs to the Generic Host

- **Keep the invocation contract.** A job that an external scheduler (Task Scheduler, cron, a triggered
  WebJob, a container job) starts once per trigger stays one-shot: run, set the exit code, exit. Do not
  turn it into a permanent loop — the scheduler is already the loop.
- A **continuous** runner — loop, sleep, repeat — becomes a `BackgroundService` whose delay takes the
  stopping token. A legacy `Task.Delay(sleep)` without a token blocks shutdown.
- Map the runner's own switches — run-once, delay, period — to configuration explicitly. The command-line
  provider ignores single-dash switches unless mapped, and a bare flag is not a value.
- Return a non-zero exit code whenever the occurrence was not completed — a failed run or a lost claim —
  and set it explicitly. Do not rely on an unhandled exception to produce one.
- While the legacy executable is still scheduled, its port is a second copy of the same job. Step 6
  applies to it exactly as it does to a web-hosted job, with **aligned windows** as the schedule model.

Code: [ref/porting-patterns.md](ref/porting-patterns.md).

## Step 6: Guard against duplicate execution

Applies to every **single-executor** job (Step 2) that can run in more than one place at once: in both
hosts during side-by-side, in several instances of one host, in two IIS worker processes during an
overlapped recycle, in old and new versions during a rolling deployment, or as a legacy console job
still scheduled next to its port.

### Invariants

1. **Every copy takes the same guard** — Framework and Core, every instance. A guard only the new host
   takes is not a guard. The Framework job changes too, or is verifiably stopped first.
2. **Mutual exclusion is not one run per occurrence.** A lock stops two runs overlapping; it does not
   stop the Framework host running at 10:00 and the Core host running again at 10:00:05. The next-due
   time must live in the shared store, decided in the same atomic step as the claim.
3. **Decide with the store's clock**, never a host clock. Hosts drift.
4. **Fail closed.** If the store cannot be reached, the job does not run.
5. **Renew while running**, and cancel the work as soon as a renewal fails or cannot be confirmed — and
   when the lease runs out before one is confirmed, even if the renewal request is still stalled.
6. **A claim reduces duplicates; it cannot eliminate them.** A holder that crashes after its side
   effects but before recording the occurrence is retried, and so is one that finishes after its lease
   expired, so delivery is **at-least-once**. Make every protected effect idempotent — a natural key, an
   upsert, an idempotency key the receiver honours — or fenced: in the same transaction as the write, under
   an update lock, check the claim's generation, an active holder, and a live lease — see
   [Fencing a write](ref/duplicate-execution-guard.md#fencing-a-write). A fence only protects writes that
   run it, and a generation check alone is not a fence: Fail, Complete, and an expired but unclaimed lease
   all keep the generation. Keep each fenced transaction well under the renewal interval, or it blocks the
   holder's own renewal; split long work into short fenced batches.
7. **Key idempotency on the occurrence, fence on the attempt.** The generation changes on every claim,
   retries included, so an idempotency key built from it lets the retry repeat the effect. Build keys from
   the job name and the occurrence's due time, which retries share. Mail and third-party calls cannot be
   fenced; give them that key, or record that the user accepts a rare duplicate.
8. **Decide what a failed run means, per job.** Either retry the same occurrence after a delay the store
   enforces — so hosts do not retry hot — or end it and wait for the next interval, as WebBackgrounder did.
   Neither is a safe default for every job.
9. **Pick the schedule model per job.** Fixed delay (next run one interval after the last ended) matches
   in-process loops. A job an external scheduler starts on a calendar needs aligned windows, or a long run
   makes the next trigger find nothing due.
10. **Record the delivery guarantee, failure policy, and schedule model per job in `task.md`.**
    At-least-once is this recipe; at-most-once means completing before acting and accepting a lost
    occurrence when a holder crashes.

### Choose a guard

| Guard | Stops a recorded occurrence running again | Fencing token | Needs | Use when |
|---|---|---|---|---|
| SQL schedule row | yes — next-due time in the row, fixed delay or aligned windows | `Generation` column | one new table, SQL Server 2012+ or Azure SQL | both hosts reach a shared SQL Server database (default) |
| Azure blob lease with metadata | yes — approximate fixed delay in blob metadata | generation in metadata | a storage account, one blob per job, and a Framework claim you write and test yourself | no shared SQL database |
| `sp_getapplock` | no — mutex only | none | nothing | only alongside a next-due row, or where the job's own data records progress |
| Dedicated single worker process | no | none | a deployment change | moving the job out of the web hosts — and still take a claim: a replica count of one is not a mutex during rolling deployments or restarts |
| Configuration switch per job | no | none | configuration | a kill switch only; per-instance configuration is not atomic during a rollout |

Recipes, the Framework-side code, and worked examples: [ref/duplicate-execution-guard.md](ref/duplicate-execution-guard.md).
The Core-side reference is [ref/scheduled-singleton-job.cs](ref/scheduled-singleton-job.cs).

**An existing `WebFarmJobCoordinator` is not reusable as-is.** Two hosts using two different guards have
no guard. Either the Core port reserves through the **same** `WorkItems` table with the same `JobName`,
the same transaction, and the same timeout — which keeps the old mutex-only behaviour — or both hosts move
to the schedule row, Framework first. Moving is two Framework deployments: add the claim and **keep** the
coordinator, then remove the coordinator once every instance takes the claim. Removing it in the same
deployment leaves old and new instances holding different guards for the length of the rollout.

**The schedule table is a schema change.** Load `managing-shared-database-schema` before creating it:
`get_instructions(kind='skill', query='managing-shared-database-schema')`. The table is an additive new
table created and seeded by the single schema owner's migration. Application logins hold DML only during
the window, so the application never runs `CREATE TABLE` at startup.

### Handover

A rolling deployment of the guard is itself a window in which guarded and unguarded processes coexist, so
the guard is activated only once no unguarded process remains:

1. The schema owner creates the schedule table and seeds one row per job — interval and schedule model
   included — **inactive**: `NextDueUtc` far in the future, so no guarded copy runs yet.
2. Deploy the guard into the **Framework** job, on every instance. Wait until no unguarded process
   remains: the rollout has finished, old IIS worker processes have exited, and no unguarded console copy
   is still scheduled.
3. Activate: one `UPDATE` sets each row's `NextDueUtc` to its first occurrence. The job does not run between
   the last unguarded process stopping and this step, so keep that gap short. Confirm each run then
   advances `Generation` and that no run happens without a claim.
4. Deploy the Core port under the same job name. It reads the interval from the row, so the two hosts
   cannot disagree about it.
5. Watch several occurrences: one holder per generation, no overlap while leases are live, and no recorded
   occurrence run again.
6. Retire the Framework copy whenever convenient. Never remove the guard while two copies can run.

**IIS keeps the Framework side moving under you.** With default settings an application pool stops after
20 idle minutes and starts on demand, so as traffic drains to Core, the Framework host's in-process jobs
silently stop — the guard lets Core claim the work, but per-instance jobs there simply stop. Overlapped
recycling briefly runs two worker processes, so a single-instance Framework host overlaps itself.

## Step 7: Shutdown, startup, and failure policy

- Pass the stopping token through every `await`. Raise `HostOptions.ShutdownTimeout` if a run needs
  longer than 30 seconds to wind down; work that ignores cancellation is abandoned at the timeout.
- Since .NET 6 an exception escaping `ExecuteAsync` **stops the host** — in a web host, the whole site.
  Preserve the legacy failure policy deliberately: if the old scheduler logged a failed run and carried
  on, catch per run, log, back off, and report consecutive failures to a health check. Let configuration
  and invariant errors at startup fail fast. Do not set `BackgroundServiceExceptionBehavior.Ignore`
  globally as a substitute.
- From .NET 10 all of `ExecuteAsync` runs off the startup path. On earlier targets its synchronous prefix
  blocks startup, so reach the first `await` immediately.
- A legacy run at startup — a constructor that did the work, or a QBWI kick — becomes the first
  iteration of `ExecuteAsync`, not constructor or `StartAsync` code.
- A `BackgroundService` is a singleton. Create a DI scope per run with `IServiceScopeFactory`; never
  inject a scoped `DbContext` into it.

## Step 8: Verify

- Per-instance jobs log runs from **both** hosts.
- Single-executor jobs, with both hosts against one store: runs never overlap while leases are live, and
  once an occurrence is recorded neither host runs it again; kill the holder mid-run and another host retries the same
  occurrence after the lease expires — the expected at-least-once repeat; a run that outlives its lease is
  not recorded; make the store unreachable and nothing runs while both hosts stay up; stop a host and its
  claim is released.
- The fence, for jobs that use one: suspend the holder past its lease (debugger or process suspend), let
  another host claim, resume, and confirm the stale attempt's fenced write is rejected with error 50002.
- A failing run leaves the web host serving, shows in the health check, and is retried or ended as the
  job's failure policy says.
- Request queues are bounded and behave as decided when full.
- One-shot console jobs return non-zero whenever the occurrence was not completed.

## Decomposition Rules

*(Read by the task-breaker when this skill is attached to a task being decomposed. Both `task-breaker`
and `task-executor` scan for this exact heading — do not rename it.)*

**Restate the pin on every job subtask.** A subtask's `task.md` is written from the breakdown alone, so a
parent's `#skill:` pin does not reach it. Copy `#skill:migrating-inprocess-background-jobs` into every
subtask that ports, enables, schedules, guards, or retires a background job.

**Pin the schema skill where the store is created.** A subtask that creates or seeds the schedule table
also carries `#skill:managing-shared-database-schema`.

**Order the work.** Inventory and classification first; the guard in the Framework host before any
single-executor job is enabled in the Core host; the Core port next; retiring the legacy copy last.
Never create a subtask that enables a single-executor job in the Core host while any copy runs unguarded.

## Success criteria

- Inventory and classification written to `task.md`, every row citing `path:line`
- Per-instance jobs run in every instance of both hosts, unguarded
- Every single-executor job takes the same guard in every copy, with its next-due time in the shared store
- Delivery guarantee, failure policy, and schedule model recorded per job; protected effects idempotent,
  keyed by the occurrence, or fenced on generation, active holder, and live lease
- The schedule table created by the schema owner's migration, never by the application
- No legacy `Task` started unawaited, no `async void` job body, no scoped service captured by a job
- A failed run does not stop the web host; shutdown cancels runs and releases claims
- One-shot console jobs keep their scheduler and their exit codes
