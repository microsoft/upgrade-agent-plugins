# Duplicate-Execution Guard

Recipes for Step 6 of `migrating-inprocess-background-jobs`. Read the invariants in the skill body first;
this file shows how to meet them.

## Contents

- [Delivery guarantee](#delivery-guarantee)
- [SQL schedule row](#sql-schedule-row)
- [Framework-side claim](#framework-side-claim)
- [Fencing a write](#fencing-a-write)
- [Worked example: two hosts, one job](#worked-example-two-hosts-one-job)
- [sp_getapplock](#sp_getapplock)
- [Azure blob lease](#azure-blob-lease)
- [Replacing WebFarmJobCoordinator](#replacing-webfarmjobcoordinator)

## Delivery guarantee

A claim is held for a lease duration and renewed while the job runs. These events can still produce a
second run of one occurrence, or none:

| Event | Result | Protection |
|---|---|---|
| Holder crashes after its effects, before recording the occurrence | the occurrence is due again once the lease expires; another holder re-runs it | idempotent effects, keyed by the occurrence |
| Holder pauses longer than its lease (GC, VM freeze, lost network), then continues | two holders overlap | fenced writes |
| Holder finishes after its lease expired | its completion is rejected; the occurrence runs again | idempotent effects |
| Store unreachable | nobody runs | fail closed — the occurrence waits |

This is **at-least-once**. For **at-most-once**, complete the occurrence before acting and accept that a
crash loses it. Record the choice per job.

Each claim carries two identities. Keep them apart:

| Identity | Changes when | Use it for |
|---|---|---|
| `DueUtc` (`JobOccurrence.IdempotencyKey`) | the occurrence is completed and the next one scheduled | idempotency keys on effects outside the database |
| `Generation` (`JobOccurrence.FencingToken`) | every claim, retries included | fenced writes in the database |

An idempotency key built from the generation changes on the retry, so the receiver sees a new request and
repeats the effect.

## SQL schedule row

One row per job. The row owns the next-due time, the lease, and a generation that increases on every
claim. Created and seeded by the schema owner's migration — load `managing-shared-database-schema` first.

```sql
CREATE TABLE dbo.BackgroundJobSchedule
(
    JobName         nvarchar(128) NOT NULL CONSTRAINT PK_BackgroundJobSchedule PRIMARY KEY,
    IntervalSeconds int           NOT NULL CONSTRAINT CK_BackgroundJobSchedule_Interval CHECK (IntervalSeconds > 0),
    AlignToInterval bit           NOT NULL,
    NextDueUtc      datetime2(3)  NOT NULL,
    Holder          nvarchar(256) NULL,
    LeaseUntil      datetime2(3)  NOT NULL,
    Generation      bigint        NOT NULL,
    Attempts        int           NOT NULL
);

-- Seeded inactive. Activate it only after every copy of the job takes the guard (see the skill's Handover):
INSERT INTO dbo.BackgroundJobSchedule (JobName, IntervalSeconds, AlignToInterval, NextDueUtc, Holder, LeaseUntil, Generation, Attempts)
VALUES (N'expire-stale-records', 3600, 0, '9999-12-31', NULL, SYSUTCDATETIME(), 0, 0);
```

Activation, once no unguarded process remains — for an aligned row, use the next boundary instead:

```sql
UPDATE dbo.BackgroundJobSchedule SET NextDueUtc = SYSUTCDATETIME() WHERE JobName = N'expire-stale-records';
```

`AlignToInterval` chooses the schedule model:

| Value | Next occurrence | Use for |
|---|---|---|
| `0` — fixed delay | one interval after the previous run **ends** | ports of WebBackgrounder and other in-process loops, which behaved this way |
| `1` — aligned windows | the window after the occurrence that just ran, with windows counted from 2000-01-01 UTC (on the hour for 3600) | jobs an external scheduler starts on a calendar, where every trigger must find its window due |

With fixed delay, an hourly external trigger can find the job not yet due — a run that ends at 10:10
schedules 11:10, and the 11:00 trigger skips it. With aligned windows, the 11:00 trigger finds the 11:00
window due, and any other copy triggered inside that window finds it already completed.

Aligned windows advance from the occurrence, never from the completion time, so a run that overruns its
window does not skip the next one: a 10:00 run that ends at 11:10 leaves 11:00 due, and the next poll or
trigger runs it. A window nobody has attempted at all is **coalesced**, not replayed — a claim made in the
14:00 window takes the 14:00 occurrence even if 12:00 and 13:00 never ran. An occurrence that has been
attempted is never coalesced: `Attempts` counts claims since the last completion, so a retry that crosses
a window boundary — an 11:00 failure retried at 12:05 — keeps the 11:00 occurrence and its idempotency key.
Seed aligned rows with a boundary as their first `NextDueUtc`.

The six statements are the `ClaimSql`, `RenewSql`, `CompleteSql`, `FailSql`, `ReleaseSql` and `IsDueSql` constants
in [scheduled-singleton-job.cs](scheduled-singleton-job.cs). They use `THROW`, so the database must be
SQL Server 2012 or later, or Azure SQL. What each one guarantees:

| Operation | Succeeds only when | Then |
|---|---|---|
| Claim | the row exists (otherwise error 50001), `NextDueUtc` has passed, and no lease is live | returns `Generation + 1` and the occurrence's `NextDueUtc`, moved up to the current window only for an aligned occurrence nobody has attempted; counts the attempt |
| Renew | holder and generation match and the lease is live | lease extended |
| Complete | holder and generation match and the lease is live | lease cleared; next occurrence scheduled; attempts reset |
| Fail | holder and generation match and the lease is live | the same occurrence stays due; no one may claim it for the retry delay |
| Release | holder and generation match | lease cleared; the occurrence stays due for an immediate retry |
| Is due | — (read only) | whether the current occurrence is due and unrecorded; after a failed claim, separates nothing-to-do from held or deferred |

Release runs only when a run never reached Complete or Fail. Once either has been attempted — even an
attempt that threw — the claim is left to expire, because releasing after a half-finished record would make
the occurrence claimable at once, skipping the retry delay or repeating a run that completed.

Each is one `UPDATE` with its whole condition in the `WHERE` clause, so racing hosts serialize on the row
and exactly one claim wins. Every time comes from `SYSUTCDATETIME()` on the server. A job with no row
fails loudly instead of silently never running. Seed one row per job; the interval in the row is the
interval — hosts carry only a short poll interval.

Fail reuses the lease column as a backoff: `LeaseUntil` moves to the retry time with no holder, and Claim
refuses any row whose lease is live. So a failing occurrence is retried by whichever host polls first after
the delay, not hammered by every host at once.

The application login needs `SELECT` and `UPDATE` on this table and nothing else. Changing an interval or
resetting a row is an operational change made through the same migration path.

Core side: `SqlJobScheduleStore` and `SingletonScheduledJob` in
[scheduled-singleton-job.cs](scheduled-singleton-job.cs); registration in
[porting-patterns.md](porting-patterns.md#webbackgrounder-job).

## Framework-side claim

The Framework copy of the job takes the same claim. This class targets .NET Framework 4.6.2+ with C# 7.3
and `System.Data.SqlClient`, and runs the same six statements:

```csharp
using System;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Globalization;
using System.Threading;

public sealed class SqlJobClaim : IDisposable
{
    private const string ClaimSql = @"
IF NOT EXISTS (SELECT 1 FROM dbo.BackgroundJobSchedule WHERE JobName = @jobName)
    THROW 50001, 'dbo.BackgroundJobSchedule has no row for this job. Seed it in the migration that creates the table.', 1;

UPDATE dbo.BackgroundJobSchedule
SET Holder = @holder,
    LeaseUntil = DATEADD(second, @leaseSeconds, SYSUTCDATETIME()),
    Generation = Generation + 1,
    Attempts = Attempts + 1,
    NextDueUtc = CASE
        WHEN AlignToInterval = 1 AND Attempts = 0 AND NextDueUtc < DATEADD(second, DATEDIFF(second, '2000-01-01', SYSUTCDATETIME()) / IntervalSeconds * IntervalSeconds, CAST('2000-01-01' AS datetime2(3)))
        THEN DATEADD(second, DATEDIFF(second, '2000-01-01', SYSUTCDATETIME()) / IntervalSeconds * IntervalSeconds, CAST('2000-01-01' AS datetime2(3)))
        ELSE NextDueUtc
    END
OUTPUT inserted.Generation, inserted.NextDueUtc
WHERE JobName = @jobName
  AND NextDueUtc <= SYSUTCDATETIME()
  AND LeaseUntil < SYSUTCDATETIME();";

    private const string RenewSql = @"
UPDATE dbo.BackgroundJobSchedule
SET LeaseUntil = DATEADD(second, @leaseSeconds, SYSUTCDATETIME())
WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
  AND LeaseUntil >= SYSUTCDATETIME();";

    private const string CompleteSql = @"
UPDATE dbo.BackgroundJobSchedule
SET Holder = NULL,
    LeaseUntil = SYSUTCDATETIME(),
    Attempts = 0,
    NextDueUtc = CASE WHEN AlignToInterval = 1
        THEN DATEADD(second, (DATEDIFF(second, '2000-01-01', NextDueUtc) / IntervalSeconds + 1) * IntervalSeconds, CAST('2000-01-01' AS datetime2(3)))
        ELSE DATEADD(second, IntervalSeconds, SYSUTCDATETIME())
    END
WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
  AND LeaseUntil >= SYSUTCDATETIME();";

    private const string FailSql = @"
UPDATE dbo.BackgroundJobSchedule
SET Holder = NULL,
    LeaseUntil = DATEADD(second, @retrySeconds, SYSUTCDATETIME())
WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
  AND LeaseUntil >= SYSUTCDATETIME();";

    private const string ReleaseSql = @"
UPDATE dbo.BackgroundJobSchedule
SET Holder = NULL, LeaseUntil = SYSUTCDATETIME()
WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation;";

    private const string IsDueSql = @"
SELECT CASE WHEN NextDueUtc <= SYSUTCDATETIME() THEN 1 ELSE 0 END
FROM dbo.BackgroundJobSchedule
WHERE JobName = @jobName;";

    // Unique per process start, like the Core store's holder.
    private static readonly string Holder =
        Environment.MachineName + "/" + Process.GetCurrentProcess().Id + "/" + Guid.NewGuid().ToString("N");

    private readonly string connectionString;
    private readonly string jobName;
    private readonly int leaseSeconds;
    private readonly CancellationTokenSource lost = new CancellationTokenSource();
    private readonly Timer renewal;
    private readonly TimeSpan renewEvery;
    private bool recordAttempted;
    private bool disposed;

    private SqlJobClaim(string connectionString, string jobName, int leaseSeconds, long generation, DateTime dueUtc, TimeSpan renewEvery, long claimSent)
    {
        this.connectionString = connectionString;
        this.jobName = jobName;
        this.leaseSeconds = leaseSeconds;
        FencingToken = generation;
        DueUtc = DateTime.SpecifyKind(dueUtc, DateTimeKind.Utc);

        // Watchdog: Lost fires when the lease runs out without a confirmed renewal, even while a renewal request
        // is stuck inside the timer callback.
        lost.CancelAfter(Remaining(claimSent));

        // One-shot, re-armed only after each renewal finishes: renewals never overlap, so an older, slower
        // response can never pull the watchdog back after a newer one pushed it out.
        this.renewEvery = renewEvery;
        renewal = new Timer(_ => Renew(), null, renewEvery, Timeout.InfiniteTimeSpan);
    }

    /// <summary>Changes on every claim. Fenced writes compare it.</summary>
    public long FencingToken { get; private set; }

    /// <summary>Unchanged by retries: identifies the occurrence.</summary>
    public DateTime DueUtc { get; private set; }

    /// <summary>The same for every attempt at this occurrence; matches the Core reference's key.</summary>
    public string IdempotencyKey
    {
        get { return jobName + "/" + DueUtc.ToString("yyyy-MM-ddTHH:mm:ss.fff", CultureInfo.InvariantCulture) + "Z"; }
    }

    /// <summary>Fires when renewal fails or the lease runs out unrenewed. Stop the work: another holder may already be running.</summary>
    public CancellationToken Lost { get { return lost.Token; } }

    /// <summary>Null when the job is not due or another holder has it. Throws when SQL cannot be reached.</summary>
    public static SqlJobClaim TryClaim(string connectionString, string jobName, TimeSpan lease, TimeSpan renewEvery)
    {
        // A zero renewal interval makes Timer fire once, so a long run would never learn it lost the claim.
        if (lease < TimeSpan.FromSeconds(1) || renewEvery <= TimeSpan.Zero || renewEvery.Ticks > lease.Ticks / 3)
        {
            throw new ArgumentOutOfRangeException(nameof(renewEvery),
                "Use a lease of at least one second, renewed at a positive interval of at most a third of the lease.");
        }

        var leaseSeconds = (int)Math.Ceiling(lease.TotalSeconds);
        using (var connection = new SqlConnection(connectionString))
        using (var command = Command(connection, ClaimSql, jobName, leaseSeconds, null))
        {
            connection.Open();

            // The lease starts on the server after this instant, so a deadline counted from here is conservative.
            var claimSent = Stopwatch.GetTimestamp();
            using (var reader = command.ExecuteReader())
            {
                return reader.Read()
                    ? new SqlJobClaim(connectionString, jobName, leaseSeconds, reader.GetInt64(0), reader.GetDateTime(1), renewEvery, claimSent)
                    : null;
            }
        }
    }

    /// <summary>Ends the occurrence. False when the claim was lost; the occurrence then runs again.</summary>
    public bool Complete()
    {
        return Record(CompleteSql, null);
    }

    /// <summary>
    /// After TryClaim returned null: true when the occurrence is due but held or deferred — not finished — and
    /// false when there is nothing to do.
    /// </summary>
    public static bool IsDue(string connectionString, string jobName)
    {
        using (var connection = new SqlConnection(connectionString))
        using (var command = new SqlCommand(IsDueSql, connection))
        {
            command.Parameters.Add("@jobName", SqlDbType.NVarChar, 128).Value = jobName;
            connection.Open();
            return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) == 1;
        }
    }

    /// <summary>Keeps the occurrence due, unclaimable until the delay passes. False when the claim was lost.</summary>
    public bool Fail(TimeSpan retryAfter)
    {
        return Record(FailSql, (int)Math.Ceiling(retryAfter.TotalSeconds));
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        StopRenewing();
        if (!recordAttempted)
        {
            try
            {
                Rows(ReleaseSql, null);
            }
            catch (SqlException)
            {
                // Expiry releases the claim regardless.
            }
        }

        // Disarmed in StopRenewing; disposing also drops the finished job's registrations.
        lost.Dispose();
    }

    private bool Record(string sql, int? retrySeconds)
    {
        StopRenewing();

        // Once recording has been attempted, never release: a half-finished attempt followed by a release would
        // make the occurrence claimable at once. The lease expires on its own instead.
        recordAttempted = true;
        return Rows(sql, retrySeconds) == 1;
    }

    private void Renew()
    {
        try
        {
            var sent = Stopwatch.GetTimestamp();
            if (Rows(RenewSql, null) != 1)
            {
                lost.Cancel();
                return;
            }

            // The renewed lease started after this request was sent: push the watchdog out from there.
            lost.CancelAfter(Remaining(sent));
        }
        catch (Exception)
        {
            // An unconfirmed renewal is a lost claim. Never let a timer callback throw.
            lost.Cancel();
            return;
        }

        try
        {
            renewal.Change(renewEvery, Timeout.InfiniteTimeSpan);
        }
        catch (ObjectDisposedException)
        {
            // Renewal was stopped while this one ran.
        }
    }

    private TimeSpan Remaining(long sentTimestamp)
    {
        var elapsed = TimeSpan.FromSeconds((Stopwatch.GetTimestamp() - sentTimestamp) / (double)Stopwatch.Frequency);
        var remaining = TimeSpan.FromSeconds(leaseSeconds) - elapsed;
        return remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero;
    }

    private void StopRenewing()
    {
        using (var stopped = new ManualResetEvent(false))
        {
            if (renewal.Dispose(stopped))
            {
                stopped.WaitOne();
            }
        }

        // The run is over: disarm the watchdog so a finished job's Lost callbacks never fire.
        lost.CancelAfter(Timeout.InfiniteTimeSpan);
    }

    private int Rows(string sql, int? retrySeconds)
    {
        using (var connection = new SqlConnection(connectionString))
        using (var command = Command(connection, sql, jobName, leaseSeconds, FencingToken))
        {
            if (retrySeconds.HasValue)
            {
                command.Parameters.Add("@retrySeconds", SqlDbType.Int).Value = retrySeconds.Value;
            }

            connection.Open();
            return command.ExecuteNonQuery();
        }
    }

    private static SqlCommand Command(SqlConnection connection, string sql, string jobName, int leaseSeconds, long? generation)
    {
        var command = new SqlCommand(sql, connection);
        command.Parameters.Add("@jobName", SqlDbType.NVarChar, 128).Value = jobName;
        command.Parameters.Add("@holder", SqlDbType.NVarChar, 256).Value = Holder;
        command.Parameters.Add("@leaseSeconds", SqlDbType.Int).Value = leaseSeconds;
        if (generation.HasValue)
        {
            command.Parameters.Add("@generation", SqlDbType.BigInt).Value = generation.Value;
        }

        return command;
    }
}
```

Use it inside the legacy job. The task returned is already started, which `JobHost` accepts. This job
retries a failed occurrence after five minutes; choose the failure policy per job. Two things to set on
the `JobManager` first:

- **`RestartSchedulerOnFailure = true`, with a `Fail(...)` handler that logs.** The example faults its
  task on a store error, a lost claim, or a rejected completion. With the default, `false`, and a
  coordinator that lets faults through — `SingleServerJobCoordinator`, `WebFarmJobCoordinator` — one
  faulted run stops the manager's timer, and every job in it stops until the next recycle.
- **The interval.** The row decides when the job is actually due, so the WebBackgrounder interval becomes
  a poll and can be short — but only once `WebFarmJobCoordinator` is gone. While it remains, every poll
  inserts a `WorkItems` row, and nothing ever prunes them; keep the job's original interval until then.

```csharp
public override Task Execute()
{
    return Task.Run(() =>
    {
        using (var claim = SqlJobClaim.TryClaim(connectionString, "expire-stale-records",
            lease: TimeSpan.FromSeconds(60), renewEvery: TimeSpan.FromSeconds(20)))
        {
            if (claim == null)
            {
                return;
            }

            try
            {
                records.ExpireStale(claim.FencingToken, claim.Lost);
            }
            catch (Exception) when (!claim.Lost.IsCancellationRequested)
            {
                claim.Fail(TimeSpan.FromMinutes(5));
                throw;
            }

            // A run that saw Lost fire is interrupted however it returned: never record it.
            claim.Lost.ThrowIfCancellationRequested();

            // The store rejects completion unless the claim is still live. A rejected completion means the
            // occurrence was not recorded and will run again: fault the task so the scheduler reports it.
            if (!claim.Complete())
            {
                throw new InvalidOperationException("The claim was lost before the run was recorded; the occurrence will run again.");
            }
        }
    });
}
```

A legacy console job does the same in `Main`, around its work, and loops until nothing is due — the same
rule as the Core recipe's `RunUntilCaughtUpAsync`. After a completed occurrence it claims again, because
with aligned windows the completion may have been an older occurrence's retry and its own window may still
be due. When `TryClaim` returns null it calls `IsDue`: false means nothing is due, exit 0; true means an
occurrence is due but held or deferred, so wait and try again until it resolves or a deadline passes. Any
other ending — a failed run, a lost claim, the deadline — exits non-zero.

## Fencing a write

A paused holder can wake after another has claimed the job, or after its own attempt was recorded as
failed or complete. Fence the writes that must not be applied by a stale attempt: check the generation and
an active holder under an update lock in the **same transaction** as the write, so a new claim cannot slip
in between. The holder check matters because Fail keeps the generation and moves `LeaseUntil` forward as
the retry delay — without it, a failed attempt's late writes would pass the fence.

```sql
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM dbo.BackgroundJobSchedule WITH (UPDLOCK, HOLDLOCK)
               WHERE JobName = @jobName AND Generation = @generation
                 AND Holder IS NOT NULL AND LeaseUntil >= SYSUTCDATETIME())
    THROW 50002, 'Stale claim: this attempt no longer holds the job.', 1;

-- the job's writes for this batch

COMMIT TRANSACTION;
```

Only writes in the same database can be fenced this way. For anything else — mail, queues, third-party
APIs — send `JobOccurrence.IdempotencyKey` so the receiver can discard a repeat, or record that the user
accepts a rare duplicate.

**Keep each fenced transaction short.** `UPDLOCK, HOLDLOCK` holds the schedule row until commit — the row
that the holder's own renewal and every host's claim update. A fenced transaction longer than the renewal
interval, or the command timeout (30 seconds by default), makes the holder's renewal time out: the job
treats that as a lost claim, cancels, and the next poll runs the same batch again, so the job never
finishes; other hosts' claims time out on the same lock meanwhile. Split long work into many short fenced
batches, each well under both.

## Worked example: two hosts, one job

`expire-stale-records` runs hourly with fixed delay. Both hosts poll every 30 seconds with a 60-second lease.

| Time | Framework host | Core host | Row after |
|---|---|---|---|
| 10:00:00 | claims: due, no lease → generation 41, occurrence 10:00:00 | — | lease to 10:01:00, gen 41 |
| 10:00:10 | running | claim fails: live lease | unchanged |
| 10:00:20 | renews | — | lease to 10:01:20 |
| 10:00:30 | completes | — | next due 11:00:30, no lease |
| 10:00:40 | — | claim fails: **not due** | unchanged |
| 11:00:30 | claim fails: Core won the race | claims → generation 42, occurrence 11:00:30 | lease to 11:01:30, gen 42 |
| 11:00:50 | — | process killed mid-run | lease still to 11:01:30 |
| 11:01:40 | claims: due, lease expired → generation 43, same occurrence 11:00:30 | — | gen 43 |

Row 10:00:40 is the case a lock alone gets wrong: without the next-due time in the row, the Core host
would have run the same occurrence again. Row 11:01:40 is the at-least-once retry: a new fencing token,
the same idempotency key. The job's deletes are idempotent, so the re-run is harmless.

## sp_getapplock

A SQL Server application lock is a **mutex only**: it carries no next-due time and no fencing token. It
needs no schema, which makes it useful around a job whose own data already records progress — a queue
table with a processed flag — but on its own it does not stop sequential duplicates.

```sql
DECLARE @result int;
EXEC @result = sp_getapplock @Resource = @resource, @LockMode = 'Exclusive',
                             @LockOwner = 'Session', @LockTimeout = 0;
IF @result < 0
    THROW 50003, 'Another holder is running this job.', 1;
```

`sp_getapplock` reports failure through its return value, not an error, so the check is what makes it
fail closed. `@LockTimeout = 0` skips immediately when another holder is running. The lock belongs to the
connection that took it, which must stay open for the whole run; if that connection drops, the lock is
released while the job may still be running, and nothing tells it to stop.

## Azure blob lease

For hosts that share a storage account but not a database. One blob per job carries the schedule in its
metadata; the lease is the claim. Lease durations are 15 to 60 seconds. Provision the blob with its
metadata at deployment, as the schema owner seeds the SQL row:

| Metadata key | Initial value |
|---|---|
| `intervalseconds` | the job's interval in seconds |
| `nextdueutc` | far in the future until activation, as for the SQL row; then any past instant, round-trip format (`O`) |
| `generation` | `0` |

Core side, with `Azure.Storage.Blobs` 12.x. Times come from the storage service's `Date` response header,
never the host clock:

```csharp
public sealed class BlobJobScheduleStore(BlobContainerClient container, TimeSpan leaseDuration) : IJobScheduleStore
{
    // The service accepts finite leases of 15 to 60 seconds.
    public TimeSpan LeaseDuration { get; } = leaseDuration >= TimeSpan.FromSeconds(15) && leaseDuration <= TimeSpan.FromSeconds(60)
        ? leaseDuration
        : throw new ArgumentOutOfRangeException(nameof(leaseDuration), "Blob leases last 15 to 60 seconds.");

    public async Task<IJobClaim?> TryClaimDueAsync(string jobName, CancellationToken cancellationToken)
    {
        var blob = container.GetBlobClient($"background-jobs/{jobName}");
        var lease = blob.GetBlobLeaseClient();
        try
        {
            await lease.AcquireAsync(LeaseDuration, cancellationToken: cancellationToken);
        }
        catch (RequestFailedException ex) when (ex.ErrorCode == BlobErrorCode.LeaseAlreadyPresent)
        {
            return null;
        }

        try
        {
            var leased = new BlobRequestConditions { LeaseId = lease.LeaseId };
            var properties = await blob.GetPropertiesAsync(leased, cancellationToken);
            var metadata = properties.Value.Metadata;
            var now = ServiceNow(properties);
            var due = DateTimeOffset.Parse(metadata["nextdueutc"], CultureInfo.InvariantCulture);
            if (due > now || (metadata.TryGetValue("retryafterutc", out var retry)
                && DateTimeOffset.Parse(retry, CultureInfo.InvariantCulture) > now))
            {
                await lease.ReleaseAsync(cancellationToken: cancellationToken);
                return null;
            }

            var generation = long.Parse(metadata["generation"], CultureInfo.InvariantCulture) + 1;
            metadata["generation"] = generation.ToString(CultureInfo.InvariantCulture);
            await blob.SetMetadataAsync(metadata, leased, cancellationToken);
            return new Claim(blob, lease, new JobOccurrence(jobName, due.UtcDateTime, generation));
        }
        catch
        {
            await lease.ReleaseAsync(cancellationToken: CancellationToken.None);
            throw;
        }
    }

    private static DateTimeOffset ServiceNow(Response<BlobProperties> response)
        => response.GetRawResponse().Headers.Date ?? throw new InvalidOperationException("The storage response carried no Date header.");

    public async Task<bool> IsDueAsync(string jobName, CancellationToken cancellationToken)
    {
        var properties = await container.GetBlobClient($"background-jobs/{jobName}").GetPropertiesAsync(cancellationToken: cancellationToken);
        return DateTimeOffset.Parse(properties.Value.Metadata["nextdueutc"], CultureInfo.InvariantCulture) <= ServiceNow(properties);
    }

    private sealed class Claim(BlobClient blob, BlobLeaseClient lease, JobOccurrence occurrence) : IJobClaim
    {
        private bool recordAttempted;

        public JobOccurrence Occurrence => occurrence;

        public async Task<bool> RenewAsync(CancellationToken cancellationToken)
        {
            try
            {
                await lease.RenewAsync(cancellationToken: cancellationToken);
                return true;
            }
            catch (RequestFailedException)
            {
                return false;
            }
        }

        public Task<bool> CompleteAsync(CancellationToken cancellationToken)
            => RecordAsync((metadata, now) =>
            {
                // The Date header has one-second resolution; the extra second keeps a short interval from collapsing.
                var interval = TimeSpan.FromSeconds(int.Parse(metadata["intervalseconds"], CultureInfo.InvariantCulture));
                metadata["nextdueutc"] = (now + interval + TimeSpan.FromSeconds(1)).ToString("O", CultureInfo.InvariantCulture);
                metadata.Remove("retryafterutc");
            }, cancellationToken);

        public Task<bool> FailAsync(TimeSpan retryAfter, CancellationToken cancellationToken)
            => RecordAsync((metadata, now) =>
                metadata["retryafterutc"] = (now + retryAfter).ToString("O", CultureInfo.InvariantCulture), cancellationToken);

        public async ValueTask DisposeAsync()
        {
            if (!recordAttempted)
            {
                try
                {
                    await lease.ReleaseAsync(cancellationToken: CancellationToken.None);
                }
                catch (RequestFailedException)
                {
                    // Expiry releases the lease regardless.
                }
            }
        }

        private async Task<bool> RecordAsync(Action<IDictionary<string, string>, DateTimeOffset> update, CancellationToken cancellationToken)
        {
            // Never release after a record attempt, even one that failed: the lease expires on its own instead.
            recordAttempted = true;
            try
            {
                var leased = new BlobRequestConditions { LeaseId = lease.LeaseId };
                var properties = await blob.GetPropertiesAsync(leased, cancellationToken);
                var metadata = properties.Value.Metadata;
                update(metadata, ServiceNow(properties));
                await blob.SetMetadataAsync(metadata, leased, cancellationToken);
            }
            catch (RequestFailedException)
            {
                return false;
            }

            try
            {
                await lease.ReleaseAsync(cancellationToken: cancellationToken);
            }
            catch (RequestFailedException)
            {
                // Recorded already; expiry releases the lease regardless.
            }

            return true;
        }
    }
}
```

The blob variant is weaker than the SQL row, in ways to state rather than discover:

- **Fixed delay only, and approximate.** Blob metadata cannot do date arithmetic in the service, so each
  time is read from one response and written by a later request. The `Date` header has one-second
  resolution, which the extra second covers; the request delay in between is not covered. Treat the
  interval as approximate, and use the SQL row when a job needs aligned windows.
- **The generation fences nothing by itself.** It is a token only for a sink that stores and compares it.
- **Expiry is softer.** The service accepts a renewal, and lease-conditioned writes, after the lease
  expires as long as no one else has leased the blob since. Nobody else ran in that case, so the
  occurrence is still recorded once — but keep renewing well inside the lease duration.
- **The Framework half is not supplied as code.** Only the SQL row ships a compiled .NET Framework claim.
  For the blob variant, write the Framework claim from this table — every step must match the Core code
  above, or the two hosts hold two different guards:

  | Step | Request | Condition | Outcome |
  |---|---|---|---|
  | Claim | acquire a lease on `background-jobs/{job}` | 409 `LeaseAlreadyPresent` | not claimed |
  | | read properties under the lease | `nextdueutc` or `retryafterutc` later than the response `Date` | release; not claimed |
  | | write metadata under the lease with `generation` + 1 | | claimed; occurrence = `nextdueutc` |
  | Renew | renew the lease | any failure | claim lost; cancel the work |
  | Complete | write `nextdueutc` = response `Date` + interval + 1 s, remove `retryafterutc`, under the lease; then release | write fails | not recorded |
  | Fail | write `retryafterutc` = response `Date` + retry delay, under the lease; then release | write fails | not recorded |
  | Dispose | release, only if neither Complete nor Fail was attempted | | |
  | Is due | read properties without the lease | `nextdueutc` not later than the response `Date` | due but held or deferred |

  `Azure.Storage.Blobs` 12.x supports .NET Framework 4.6.2 and later; an app still on
  `WindowsAzure.Storage` or `Microsoft.Azure.Storage.Blob` can take the same lease, because the lease lives
  in the service. Run both halves together against Azurite — two processes, one blob — before rollout:
  nothing in this skill's tests covers a Framework blob claim. Where that is not practical, use the SQL
  row instead.

## Replacing WebFarmJobCoordinator

`WebFarmJobCoordinator` reserves a run by inserting into a `WorkItems` table when the job's latest row is
not active, inside a `TransactionScope`. Two consequences for side-by-side:

- It is a mutex, so the schedule-row guard is strictly stronger — but swapping one for the other is
  itself a rollout. During a rolling Framework deployment, instances not yet updated take only the
  `WorkItems` reservation while updated ones take only the claim: two guards, so no guard. Change it in
  two Framework deployments:
  1. Add the claim inside `Execute`, as above, and **keep** `WebFarmJobCoordinator` and the job's original
     interval. Every instance now takes both, and the old ones still exclude the new ones through
     `WorkItems`. Each reservation inserts a `WorkItems` row whether or not the claim then finds the job
     due, so a short poll here would grow that table by thousands of rows a day per server.
  2. Once every Framework instance runs that build, swap the coordinator for `SingleServerJobCoordinator`.
     Only now shorten the interval to a poll, and prune `WorkItems`, which WebBackgrounder never does.

  Deploy the Core port, which takes only the claim, after step 1 has reached every instance.
- Until the Framework side is changed, a Core port that does not reserve through the same `WorkItems`
  rows, with the same `JobName`, runs alongside it unguarded.
