# Porting Patterns

Code for Steps 3–5 of `migrating-inprocess-background-jobs`. Names are illustrative; keep the control
flow. Every example targets ASP.NET Core or the Generic Host.

## Contents

- [WebBackgrounder job](#webbackgrounder-job)
- [QBWI refresh loop at startup](#qbwi-refresh-loop-at-startup)
- [QBWI from a request](#qbwi-from-a-request)
- [Best-effort fire-and-forget](#best-effort-fire-and-forget)
- [IRegisteredObject](#iregisteredobject)
- [Console job](#console-job)

## WebBackgrounder job

Legacy shape:

```csharp
public class RefreshCatalogCacheJob : Job
{
    private readonly CatalogCache cache;

    public RefreshCatalogCacheJob(TimeSpan interval, CatalogCache cache)
        : base("RefreshCatalogCache", interval)
    {
        this.cache = cache;
    }

    // Unstarted task: JobHost calls Start(). Awaiting this from new code hangs forever.
    public override Task Execute() => new Task(() => cache.Refresh());
}

// Application start
var manager = new JobManager(new IJob[] { new RefreshCatalogCacheJob(TimeSpan.FromMinutes(15), cache) },
    new SingleServerJobCoordinator()) { RestartSchedulerOnFailure = true };
manager.Fail(e => Trace.TraceError(e.Message));
manager.Start();
```

The cache is process-local, so the port runs in every instance with no guard:

```csharp
public sealed class RefreshCatalogCacheJob(CatalogCache cache, ILogger<RefreshCatalogCacheJob> logger)
    : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(15);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // JobManager.Start() ran the shortest-interval job — here the only one — straight away; after that each
        // interval ran from the end of the previous run. So refresh first, then wait.
        do
        {
            try
            {
                await cache.RefreshAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // The legacy Fail handler logged and the schedule continued.
                logger.LogError(ex, "Catalog cache refresh failed.");
            }
        }
        while (await DelayAsync(Interval, stoppingToken));
    }

    private static async Task<bool> DelayAsync(TimeSpan delay, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(delay, cancellationToken);
            return true;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }
}

builder.Services.AddSingleton<CatalogCache>();
builder.Services.AddHostedService<RefreshCatalogCacheJob>();
```

A job that writes shared state derives from `SingletonScheduledJob` in
[scheduled-singleton-job.cs](scheduled-singleton-job.cs) instead. Its interval lives in the shared
schedule row; the host only polls. The options also state what a failed run means — here, retry the same
occurrence after five minutes, which is safe because expiring records is idempotent:

```csharp
public sealed class ExpireStaleRecordsJob(
    IServiceScopeFactory scopes, IJobScheduleStore store, ILogger<ExpireStaleRecordsJob> logger)
    : SingletonScheduledJob(
        new SingletonJobOptions(
            "expire-stale-records",
            PollInterval: TimeSpan.FromSeconds(30),
            RenewEvery: TimeSpan.FromSeconds(20),
            RetryFailedRunAfter: TimeSpan.FromMinutes(5)),
        store,
        logger)
{
    protected override async Task RunAsync(JobOccurrence occurrence, CancellationToken cancellationToken)
    {
        // A BackgroundService is a singleton: resolve scoped services per run.
        await using var scope = scopes.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<RecordExpiry>()
            .ExpireStaleAsync(occurrence.FencingToken, cancellationToken);
    }
}

var connectionString = builder.Configuration.GetConnectionString("App")!;
builder.Services.AddScoped<RecordExpiry>();
builder.Services.AddSingleton<IJobScheduleStore>(
    new SqlJobScheduleStore(() => new SqlConnection(connectionString), leaseDuration: TimeSpan.FromSeconds(60)));
builder.Services.AddHostedService<ExpireStaleRecordsJob>();
```

Renew at no more than a third of the lease duration, so one slow renewal does not lose the claim. Pass
`occurrence.FencingToken` to fenced database writes and `occurrence.IdempotencyKey` to anything outside
the database. Pass `RetryFailedRunAfter: null` only where the legacy behaviour — a failed run waits for the
next interval — is what the job needs.

## QBWI refresh loop at startup

Legacy shape:

```csharp
HostingEnvironment.QueueBackgroundWorkItem(async token =>
{
    while (!token.IsCancellationRequested)
    {
        await settings.RefreshAsync();
        await Task.Delay(RefreshInterval, token);
    }
});
```

In the legacy loop, one exception from `RefreshAsync` ended the loop for the life of the AppDomain, and
nothing logged it. Decide whether that was intended; it rarely is. The port refreshes immediately, as the
legacy loop did, and keeps going after a failure:

```csharp
public sealed class SettingsRefresher(SettingsCache settings, ILogger<SettingsRefresher> logger) : BackgroundService
{
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await settings.RefreshAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Settings refresh failed.");
            }

            try
            {
                await Task.Delay(RefreshInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }
}
```

## QBWI from a request

Best-effort work queued by a request becomes a bounded queue drained by one hosted service:

```csharp
public sealed class BackgroundWorkQueue
{
    private readonly Channel<Func<IServiceProvider, CancellationToken, ValueTask>> channel =
        Channel.CreateBounded<Func<IServiceProvider, CancellationToken, ValueTask>>(
            new BoundedChannelOptions(capacity: 1000) { FullMode = BoundedChannelFullMode.Wait });

    public ChannelReader<Func<IServiceProvider, CancellationToken, ValueTask>> Reader => channel.Reader;

    public ValueTask QueueAsync(Func<IServiceProvider, CancellationToken, ValueTask> work, CancellationToken cancellationToken)
        => channel.Writer.WriteAsync(work, cancellationToken);
}

public sealed class BackgroundWorkProcessor(
    BackgroundWorkQueue queue, IServiceScopeFactory scopes, ILogger<BackgroundWorkProcessor> logger)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await foreach (var work in queue.Reader.ReadAllAsync(stoppingToken))
            {
                try
                {
                    await using var scope = scopes.CreateAsyncScope();
                    await work(scope.ServiceProvider, stoppingToken);
                }
                catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
                {
                    logger.LogError(ex, "Queued background work failed.");
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
        }
    }
}

builder.Services.AddSingleton<BackgroundWorkQueue>();
builder.Services.AddHostedService<BackgroundWorkProcessor>();
```

Queue values, not request state. Capture what the work needs while the request is still running:

```csharp
var entry = new AuditEntry(User.Identity?.Name, HttpContext.Request.Path);
await queue.QueueAsync(
    (services, cancellationToken) => services.GetRequiredService<AuditWriter>().WriteAsync(entry, cancellationToken),
    HttpContext.RequestAborted);
```

Whatever is still queued when the process stops is lost. Work that must eventually run goes to a durable
queue or an outbox table instead, drained by a single-executor job.

## Best-effort fire-and-forget

Only for one-off work whose loss is acceptable. The host does not wait for it at shutdown. `Task.Run`
flows the caller's `ExecutionContext` — `AsyncLocal` values, the current principal — into the detached
work; QBWI did not, so suppress the flow:

```csharp
public sealed class BestEffortWork(IHostApplicationLifetime lifetime, ILogger<BestEffortWork> logger)
{
    public void Run(Func<CancellationToken, Task> work)
    {
        using (ExecutionContext.SuppressFlow())
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    await work(lifetime.ApplicationStopping);
                }
                catch (OperationCanceledException) when (lifetime.ApplicationStopping.IsCancellationRequested)
                {
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Best-effort background work failed.");
                }
            });
        }
    }
}
```

## IRegisteredObject

`Stop(bool immediate)` ran when the AppDomain began shutting down. Its body moves to `StopAsync`:

```csharp
public sealed class TelemetryFlusher(TelemetryBuffer buffer) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    // Bounded by HostOptions.ShutdownTimeout; the token fires when that time is up.
    public Task StopAsync(CancellationToken cancellationToken) => buffer.FlushAsync(cancellationToken);
}

builder.Services.AddSingleton<TelemetryBuffer>();
builder.Services.AddHostedService<TelemetryFlusher>();
```

## Console job

**One-shot**, started by an external scheduler. Starting the host connects Ctrl+C and SIGTERM to the
stopping token; the process exit code is the job's result. While the legacy executable can still be
scheduled next to its port, both go through the shared claim — the legacy side with the Framework code in
[duplicate-execution-guard.md](duplicate-execution-guard.md#framework-side-claim) — so whichever process
the scheduler starts first does the work and the other finds nothing due:

```csharp
var builder = Host.CreateApplicationBuilder(args);
var connectionString = builder.Configuration.GetConnectionString("App")!;
builder.Services.AddScoped<RecordExpiry>();
builder.Services.AddSingleton<IJobScheduleStore>(
    new SqlJobScheduleStore(() => new SqlConnection(connectionString), leaseDuration: TimeSpan.FromSeconds(60)));
// Not AddHostedService: this process runs what is due, then exits.
builder.Services.AddSingleton<ExpireStaleRecordsJob>();

using var host = builder.Build();
await host.StartAsync();
var stopping = host.Services.GetRequiredService<IHostApplicationLifetime>().ApplicationStopping;
var logger = host.Services.GetRequiredService<ILogger<ExpireStaleRecordsJob>>();
var job = host.Services.GetRequiredService<ExpireStaleRecordsJob>();

int exitCode;
try
{
    // Exit 0 only once nothing is due. Completing one occurrence is not enough: with aligned windows it can be an
    // older occurrence's retry, leaving this trigger's own window due. Busy — another copy running it, a crashed
    // holder's lease not yet expired, a retry delay — is waited out. Size the wait to cover the lease, the longest
    // run of another copy, and the retry delay.
    exitCode = await job.RunUntilCaughtUpAsync(maxWait: TimeSpan.FromMinutes(15), stopping) ? 0 : 1;
}
catch (Exception ex)
{
    logger.LogError(ex, "Job could not run.");
    exitCode = 1;
}

await host.StopAsync();
return exitCode;
```

`RunUntilCaughtUpAsync` returns true only when the store reports nothing due. A failed run, a lost claim,
and a wait that runs out all exit non-zero, so the scheduler reports an occurrence nobody has confirmed.
Seed the row with `AlignToInterval = 1` and the scheduler's cadence as its interval. Each trigger then
finds its own window due — however long the previous run took — and any other copy triggered inside the
same window finds it already completed. A trigger that finds an older occurrence still owed — a retry, or a
run interrupted by a crash or shutdown — runs it first and then its own window, which is why the recipe
loops until nothing is due rather than stopping after one completion. Fire the triggers a little after the
boundary — a minute past the hour — so clock jitter never starts one just before its window opens. Fixed
delay is wrong here: a run that ends at 10:10 would make the 11:00 trigger find nothing due.

**Continuous**, a loop that sleeps between runs: register a `BackgroundService` like the ones above and
call `await builder.Build().RunAsync()`.

**Legacy switches.** The command-line configuration provider ignores single-dash switches such as
`-delay 5000` unless they are mapped, and a bare flag such as `-single` either consumes the next argument
as its value or is dropped. Translate the legacy runner's switches explicitly — the names below are
placeholders for whatever the runner accepts:

```csharp
const string BareFlag = "-single";
var runOnce = args.Contains(BareFlag, StringComparer.OrdinalIgnoreCase);
var rest = args.Where(arg => !string.Equals(arg, BareFlag, StringComparison.OrdinalIgnoreCase)).ToArray();

var builder = Host.CreateApplicationBuilder(rest);
builder.Configuration.AddCommandLine(rest, new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["-delay"] = "Job:DelayMilliseconds",
    ["-period"] = "Job:PeriodSeconds",
});
builder.Configuration["Job:RunOnce"] = runOnce.ToString();
```

Check what each legacy switch meant before mapping it: a delay in milliseconds and a period in seconds
are easy to swap.
