# Worked Example: Contoso Background Jobs

This is an application binding, not a generic recipe. Type names, file paths, and intervals below belong
only to this example. Inspect the target repository's revision before applying any of it.

## Contents

- [Source contract](#source-contract)
- [Inventory and classification](#inventory-and-classification)
- [Porting the in-process jobs](#porting-the-in-process-jobs)
- [Console jobs](#console-jobs)
- [What the guard is for here](#what-the-guard-is-for-here)

## Source Contract

The Contoso sample application is a fictional, large ASP.NET MVC (.NET Framework) web application,
`Contoso.Web`, that schedules its in-process jobs with WebBackgrounder and ships a set of console jobs
beside it. The illustrative files this example reads:

- `Contoso.Web/App_Start/AppActivator.cs` — `BackgroundJobsPostStart` and `BackgroundJobsStop`, wired through WebActivatorEx assembly attributes
- `Contoso.Web/Infrastructure/Jobs/ContosoJobCoordinator.cs`
- `Contoso.Web/Infrastructure/Jobs/PackageVulnerabilitiesCacheRefreshJob.cs`
- `Contoso.Web/Infrastructure/Lucene/CloudDownloadCountServiceRefreshJob.cs`
- `Contoso.Web/Infrastructure/Lucene/LuceneIndexingJob.cs` and `LuceneIndexingService.cs`
- `Contoso.Web/App_Start/OwinStartup.cs` — the startup QBWI kicks
- `Contoso.Jobs.Common/JobRunner.cs` and, as one of its callers, `Contoso.Maintenance/Program.cs`
- `Contoso.AppHost/Program.cs`
- WebBackgrounder's `JobManager`, `JobHost`, `Schedule`, and `WebFarmJobCoordinator`

## Inventory and Classification

`BackgroundJobsPostStart` builds one `JobManager` with `RestartSchedulerOnFailure = true` and a `Fail`
handler that traces the message. Its coordinator, `ContosoJobCoordinator`, calls `job.Execute()` directly,
logs a faulted task, and returns a dummy task when `Execute` throws. There is no cross-instance
coordination: **every web instance runs every job**.

| Job | Pattern | Interval | State it changes | Classification |
|---|---|---|---|---|
| `LuceneIndexingJob` (registered by `LuceneIndexingService` when automatic index updates are enabled) | WebBackgrounder | 10 min | a Lucene index in a local file-system directory, plus a metadata marker file | per machine — see below |
| `CloudDownloadCountServiceRefreshJob` (Azure storage only) | WebBackgrounder, plus a QBWI kick at startup | 15 min | the in-memory download-count cache | per instance |
| `PackageVulnerabilitiesCacheRefreshJob` | WebBackgrounder, plus a QBWI kick at startup | 30 min | the in-memory vulnerabilities cache | per instance |
| `ContentObjectService.Refresh` loop | QBWI at startup | `ContentObjectService.RefreshInterval` (5 min) | in-memory configuration read from content storage | per instance |

Every in-process job refreshes state **inside the process** (or on its machine). None of them needs the
duplicate-execution guard. Putting them behind a shared claim would leave every host but one serving a
stale cache — the failure the classification step exists to prevent.

The Lucene index is **machine-local, not process-local**. Two processes on one machine that resolve the
same index directory — the Framework and Core hosts side by side on one server, or two worker processes
during an IIS overlapped recycle — contend for one `IndexWriter`. Give each host its own index
directory, or make one host the only writer on that machine.

## Porting the In-Process Jobs

Each job's `Execute()` returns an **unstarted** task, and two of them wrap the work in a way the port
must not copy:

- `PackageVulnerabilitiesCacheRefreshJob.Execute()` returns `new Task(() => ...RefreshCache(...))`.
  Awaited from new code without `Start()`, it never completes.
- `CloudDownloadCountServiceRefreshJob.Execute()` returns `new Task(async () => await ...RefreshAsync())`.
  That lambda is `async void`: the task completes at the first `await`, so the scheduler neither waited
  for the refresh nor saw its exceptions.
- `LuceneIndexingJob`'s constructor updates the index synchronously before the job is registered, and
  catches `SqlException` and `DataException` so a database outage does not fail startup.

Port each as a per-instance `BackgroundService` following
[porting-patterns.md](porting-patterns.md#webbackgrounder-job):

- Run immediately, then every interval. `JobManager.Start()` already ran its shortest-interval job at once,
  and the QBWI kicks (and the Lucene constructor) gave the others an immediate run too; later runs came one
  interval after the previous one finished.
- Await `RefreshAsync` and `RefreshCache` directly.
- Keep the legacy failure policy: log and continue. The Lucene constructor's "tolerate a database outage
  at startup" becomes a caught, logged first iteration rather than a blocking constructor.
- Run the three jobs as separate services. `JobManager` serialised them on one timer, but they share no
  state, so concurrency is safe — confirm that against the target revision.

The `ContentObjectService` loop becomes the `SettingsRefresher` shape in
[porting-patterns.md](porting-patterns.md#qbwi-refresh-loop-at-startup). In the legacy loop an exception
from `Refresh()` ended the loop for the life of the AppDomain without a log entry; the port logs and
continues.

## Console Jobs

The repository's console jobs share one runner. Each `Program.Main` calls
`JobRunner.Run(job, args).Wait()`. The runner:

- loops by default and runs once with `-Once`;
- sleeps `-Sleep` milliseconds, or `-Interval` seconds, between runs — 5000 ms when neither is given —
  with a `Task.Delay` that takes no cancellation token;
- returns exit code 0 on success and 1 on failure.

Port each to the Generic Host following [porting-patterns.md](porting-patterns.md#console-job): keep
one-shot jobs one-shot where an external scheduler starts them, translate the single-dash switches
explicitly, and give the continuous loop the stopping token. For this runner the legacy-switch mapping
binds the bare flag `-Once` and the value switches `-Sleep` (milliseconds) and `-Interval` (seconds):

```csharp
var once = args.Contains("-Once", StringComparer.OrdinalIgnoreCase);
var rest = args.Where(arg => !string.Equals(arg, "-Once", StringComparison.OrdinalIgnoreCase)).ToArray();

var builder = Host.CreateApplicationBuilder(rest);
builder.Configuration.AddCommandLine(rest, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["-Sleep"] = "Job:SleepMilliseconds",
    ["-Interval"] = "Job:IntervalSeconds",
});
builder.Configuration["Job:Once"] = once.ToString();
```

Unlike the in-process jobs, many of these change shared state — databases, blob containers, search
indexes. Classify each from its `Run` body. While a legacy job and its port can both be scheduled, every
one that writes shared state takes the claim from
[duplicate-execution-guard.md](duplicate-execution-guard.md), in both copies, with aligned windows matched
to the scheduler's cadence.

`Contoso.AppHost` declares each job as one Aspire resource for local orchestration. That gives one
process per job on a developer machine; the production replica count is set by the deployment target,
and a rolling deployment still overlaps old and new — so the claim is still needed there.

## What the Guard Is For Here

Applying Step 6 blindly to this application would be wrong in both directions: gating the in-process
cache refreshes starves every non-holder's cache, and skipping the console jobs leaves the legacy and
ported copies of a shared-state job both running during the window. The classification table, not the
pattern, decides which jobs take the claim.
