// Copyright (c) Microsoft Corporation. All rights reserved.

// Generic reference: a scheduled background job that runs on one holder per occurrence across every host and
// instance sharing the schedule store. Depends only on the BCL and the Microsoft.Extensions hosting and
// logging abstractions. Adapt names; keep the control flow and the SQL predicates.

using System;
using System.Data;
using System.Data.Common;
using System.Diagnostics;
using System.Globalization;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace BackgroundJobMigrationSample;

/// <summary>
/// The shared schedule. It owns when a job is next due and who is running it, so hosts never decide either
/// from their own timers or clocks.
/// </summary>
public interface IJobScheduleStore
{
    /// <summary>How long a claim lives without renewal. Jobs renew at most every third of it.</summary>
    TimeSpan LeaseDuration { get; }

    /// <summary>
    /// Claims the job's current occurrence. Returns <see langword="null"/> when it is not due yet, another
    /// holder has claimed it, or a retry delay is running. Throws when the store cannot be reached; the caller
    /// must then not run the job.
    /// </summary>
    Task<IJobClaim?> TryClaimDueAsync(string jobName, CancellationToken cancellationToken);

    /// <summary>
    /// Whether the job's current occurrence has fallen due and not been recorded yet — whether or not it can be
    /// claimed right now. Separates "nothing to do" from "due, but held or deferred" after a failed claim.
    /// </summary>
    Task<bool> IsDueAsync(string jobName, CancellationToken cancellationToken);
}

/// <summary>One scheduled occurrence of a job, as seen by the attempt that claimed it.</summary>
/// <param name="JobName">The job.</param>
/// <param name="DueUtc">When the occurrence fell due. Unchanged by retries, so it identifies the occurrence.</param>
/// <param name="FencingToken">Increases on every claim, retries included. Fenced writes compare it.</param>
public sealed record JobOccurrence(string JobName, DateTime DueUtc, long FencingToken)
{
    /// <summary>
    /// The same for every attempt at this occurrence. Send it with effects outside the database so the receiver
    /// can discard a repeat. Never derive it from <see cref="FencingToken"/>, which changes on every retry.
    /// </summary>
    public string IdempotencyKey => JobName + "/" + DueUtc.ToString("yyyy-MM-ddTHH:mm:ss.fff", CultureInfo.InvariantCulture) + "Z";
}

/// <summary>
/// A claimed occurrence. Disposing before any attempt to complete or fail it releases the claim and leaves the
/// occurrence due, so another holder retries it. After such an attempt, even one that threw, disposing leaves
/// the lease to expire.
/// </summary>
public interface IJobClaim : IAsyncDisposable
{
    JobOccurrence Occurrence { get; }

    /// <summary>Returns <see langword="false"/> when the claim has expired or another holder has taken it.</summary>
    Task<bool> RenewAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Ends the occurrence and schedules the next one by the store's clock. Returns <see langword="false"/> when
    /// the claim has expired or another holder has taken it; the occurrence then stays due and will run again.
    /// </summary>
    Task<bool> CompleteAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Keeps the occurrence due but lets no holder claim it before <paramref name="retryAfter"/> has passed.
    /// Returns <see langword="false"/> on the same conditions as <see cref="CompleteAsync"/>.
    /// </summary>
    Task<bool> FailAsync(TimeSpan retryAfter, CancellationToken cancellationToken);
}

/// <summary>What one poll did.</summary>
public enum JobRunOutcome
{
    /// <summary>Nothing to do: the current occurrence is not due yet, or is already recorded.</summary>
    NotDue,

    /// <summary>
    /// The occurrence is due but could not be claimed: another holder is running it, a crashed holder's lease
    /// has not expired yet, or a retry delay is running. Nothing ran here, and the occurrence is not finished.
    /// </summary>
    Busy,

    /// <summary>The run succeeded and the occurrence is complete.</summary>
    Completed,

    /// <summary>The run threw. The occurrence was ended or deferred according to the failure policy.</summary>
    Failed,

    /// <summary>The claim expired or was taken while running. The occurrence was not recorded and will run again.</summary>
    ClaimLost,
}

/// <param name="JobName">The schedule row this job claims.</param>
/// <param name="PollInterval">How often this host asks whether the job is due. The interval itself lives in the store.</param>
/// <param name="RenewEvery">How often a running claim is renewed. Keep it at most a third of the lease.</param>
/// <param name="RetryFailedRunAfter">
/// What a failed run means. <see langword="null"/> ends the occurrence as if it succeeded, as WebBackgrounder
/// did. A value keeps the same occurrence due and lets any host retry it after that delay.
/// </param>
public sealed record SingletonJobOptions(string JobName, TimeSpan PollInterval, TimeSpan RenewEvery, TimeSpan? RetryFailedRunAfter);

/// <summary>
/// Polls the shared schedule and runs <see cref="RunAsync"/> only for an occurrence this process has claimed.
/// The token passed to <see cref="RunAsync"/> is cancelled on shutdown and when the claim is lost.
/// </summary>
public abstract class SingletonScheduledJob : BackgroundService
{
    private readonly IJobScheduleStore store;
    private readonly ILogger logger;

    protected SingletonScheduledJob(SingletonJobOptions options, IJobScheduleStore store, ILogger logger)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(store);
        if (options.PollInterval <= TimeSpan.Zero || options.RenewEvery <= TimeSpan.Zero || options.RetryFailedRunAfter < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(options), "PollInterval and RenewEvery must be positive, RetryFailedRunAfter non-negative.");
        }

        // A renewal slower than this lets another host claim and run the occurrence before this one notices.
        if (options.RenewEvery > store.LeaseDuration / 3)
        {
            throw new ArgumentOutOfRangeException(nameof(options),
                $"RenewEvery ({options.RenewEvery}) must be at most a third of the store's lease ({store.LeaseDuration}).");
        }

        Options = options;
        this.store = store;
        this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    protected SingletonJobOptions Options { get; }

    /// <summary>Polls in a row that ran here and did not complete. Surface it through a health check.</summary>
    public int ConsecutiveFailures { get; private set; }

    /// <summary>The job body. Stop promptly when <paramref name="cancellationToken"/> fires.</summary>
    protected abstract Task RunAsync(JobOccurrence occurrence, CancellationToken cancellationToken);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await TryRunDueOccurrenceAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // The store could not be reached. The job did not run; poll again rather than stop the host.
                logger.LogError(ex, "Background job {JobName} could not reach its schedule store.", Options.JobName);
            }

            try
            {
                await Task.Delay(Options.PollInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    /// <summary>
    /// One poll. Throws <see cref="OperationCanceledException"/> when <paramref name="stoppingToken"/> interrupts
    /// a run, leaving the occurrence due for another holder.
    /// </summary>
    public async Task<JobRunOutcome> TryRunDueOccurrenceAsync(CancellationToken stoppingToken)
    {
        // The lease started on the server after this instant, so a deadline counted from here is conservative.
        var claimSent = Stopwatch.GetTimestamp();
        await using var claim = await store.TryClaimDueAsync(Options.JobName, stoppingToken);
        if (claim is null)
        {
            return await store.IsDueAsync(Options.JobName, stoppingToken) ? JobRunOutcome.Busy : JobRunOutcome.NotDue;
        }

        // Watchdog: fires when the lease runs out without a confirmed renewal, even if a renewal request is
        // stalled, so the run cannot outlive its ownership.
        using var expiry = new CancellationTokenSource(Remaining(claimSent));

        // run is cancelled only by shutdown, a lost claim, or lease expiry; renewal stops on its own token, so a
        // successful run never sees its token fire.
        using var run = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken, expiry.Token);
        using var renewal = CancellationTokenSource.CreateLinkedTokenSource(run.Token);
        var keeper = KeepClaimAsync(claim, run, expiry, renewal.Token);
        Exception? failure = null;
        try
        {
            await RunAsync(claim.Occurrence, run.Token);
        }
        catch (Exception ex) when (!run.IsCancellationRequested)
        {
            failure = ex;
        }
        catch (Exception)
        {
            // Shutdown or a lost claim interrupted the run.
        }

        // A run that saw its token cancelled is interrupted however it ended — thrown or returned — because a
        // body that observes cancellation and returns early has not done the occurrence's work.
        var ended = !run.IsCancellationRequested;
        renewal.Cancel();
        await keeper;

        // The body is over: disarm the watchdog so it cannot cancel a finished run's token afterwards.
        expiry.CancelAfter(Timeout.InfiniteTimeSpan);

        if (!ended)
        {
            // Interrupted by shutdown or by a lost claim. Either way the occurrence stays due.
            if (failure is not null)
            {
                logger.LogError(failure, "Background job {JobName} failed while being interrupted.", Options.JobName);
            }

            stoppingToken.ThrowIfCancellationRequested();
            return ClaimLost();
        }

        // The store, not this process, decides whether the claim is still live: it rejects completing or
        // failing an occurrence whose lease has expired, so work done without ownership is never recorded.
        if (failure is not null)
        {
            logger.LogError(failure, "Background job {JobName} failed.", Options.JobName);
        }

        bool recorded;
        try
        {
            recorded = failure is not null && Options.RetryFailedRunAfter is { } retryAfter
                ? await claim.FailAsync(retryAfter, CancellationToken.None)
                : await claim.CompleteAsync(CancellationToken.None);
        }
        catch
        {
            // The outcome is unconfirmed and the occurrence may run again: count it once, and let the caller
            // report the store error.
            ConsecutiveFailures++;
            throw;
        }

        if (!recorded)
        {
            return ClaimLost();
        }

        if (failure is not null)
        {
            ConsecutiveFailures++;
            return JobRunOutcome.Failed;
        }

        ConsecutiveFailures = 0;
        return JobRunOutcome.Completed;
    }

    /// <summary>
    /// One-shot use, for a process an external scheduler starts: runs due occurrences until nothing is due,
    /// waiting <see cref="SingletonJobOptions.PollInterval"/> while one is held or deferred. Returns
    /// <see langword="true"/> only when the schedule is caught up — the process's exit code should be 0 then and
    /// only then. Returns <see langword="false"/> when a run failed, a claim was lost, or <paramref name="maxWait"/>
    /// ran out. A single <see cref="JobRunOutcome.Completed"/> is not enough: with aligned windows it can be an
    /// older occurrence's retry, leaving this trigger's own window due.
    /// </summary>
    public async Task<bool> RunUntilCaughtUpAsync(TimeSpan maxWait, CancellationToken stoppingToken)
    {
        // Exit 0 only once nothing is due. A completion always rechecks: it may have been an older occurrence's
        // retry with this trigger's own window still due. maxWait bounds only the waiting while work is held or
        // deferred, and no wait runs past it.
        // Waiting time only: claiming and running occurrences do not spend the budget.
        var waited = TimeSpan.Zero;
        while (true)
        {
            switch (await TryRunDueOccurrenceAsync(stoppingToken))
            {
                case JobRunOutcome.NotDue:
                    return true;
                case JobRunOutcome.Completed:
                    continue;
                case JobRunOutcome.Busy:
                    var remaining = maxWait - waited;
                    if (remaining <= TimeSpan.Zero)
                    {
                        return false;
                    }

                    var delay = remaining < Options.PollInterval ? remaining : Options.PollInterval;
                    await Task.Delay(delay, stoppingToken);
                    waited += delay;
                    continue;
                default:
                    return false;
            }
        }
    }

    private JobRunOutcome ClaimLost()
    {
        ConsecutiveFailures++;
        logger.LogWarning("Background job {JobName} lost its claim; the occurrence will run again.", Options.JobName);
        return JobRunOutcome.ClaimLost;
    }

    private async Task KeepClaimAsync(IJobClaim claim, CancellationTokenSource run, CancellationTokenSource expiry, CancellationToken renewal)
    {
        try
        {
            while (true)
            {
                await Task.Delay(Options.RenewEvery, renewal);
                var sent = Stopwatch.GetTimestamp();

                // WaitAsync returns when the watchdog or shutdown fires even if the store ignores the token.
                if (!await claim.RenewAsync(renewal).WaitAsync(renewal))
                {
                    run.Cancel();
                    return;
                }

                // The renewed lease started after this request was sent: push the watchdog out from there.
                expiry.CancelAfter(Remaining(sent));
            }
        }
        catch (OperationCanceledException) when (renewal.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            // A renewal that cannot be confirmed is a lost claim: another holder may already be running.
            logger.LogWarning(ex, "Background job {JobName} could not renew its claim.", Options.JobName);
            run.Cancel();
        }
    }

    private TimeSpan Remaining(long sentTimestamp)
    {
        var remaining = store.LeaseDuration - Stopwatch.GetElapsedTime(sentTimestamp);
        return remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero;
    }
}

/// <summary>
/// The schedule as one row per job in a SQL Server table every host can reach. Every comparison uses the
/// database clock. Each call opens its own connection, so a dropped connection cannot silently release a claim.
/// The schema owner's migration creates the table and seeds its rows; the application never does.
/// </summary>
public sealed class SqlJobScheduleStore : IJobScheduleStore
{
    public const string ClaimSql = """
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
          AND LeaseUntil < SYSUTCDATETIME();
        """;

    public const string RenewSql = """
        UPDATE dbo.BackgroundJobSchedule
        SET LeaseUntil = DATEADD(second, @leaseSeconds, SYSUTCDATETIME())
        WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
          AND LeaseUntil >= SYSUTCDATETIME();
        """;

    public const string CompleteSql = """
        UPDATE dbo.BackgroundJobSchedule
        SET Holder = NULL,
            LeaseUntil = SYSUTCDATETIME(),
            Attempts = 0,
            NextDueUtc = CASE WHEN AlignToInterval = 1
                THEN DATEADD(second, (DATEDIFF(second, '2000-01-01', NextDueUtc) / IntervalSeconds + 1) * IntervalSeconds, CAST('2000-01-01' AS datetime2(3)))
                ELSE DATEADD(second, IntervalSeconds, SYSUTCDATETIME())
            END
        WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
          AND LeaseUntil >= SYSUTCDATETIME();
        """;

    public const string FailSql = """
        UPDATE dbo.BackgroundJobSchedule
        SET Holder = NULL,
            LeaseUntil = DATEADD(second, @retrySeconds, SYSUTCDATETIME())
        WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation
          AND LeaseUntil >= SYSUTCDATETIME();
        """;

    public const string ReleaseSql = """
        UPDATE dbo.BackgroundJobSchedule
        SET Holder = NULL, LeaseUntil = SYSUTCDATETIME()
        WHERE JobName = @jobName AND Holder = @holder AND Generation = @generation;
        """;

    public const string IsDueSql = """
        SELECT CASE WHEN NextDueUtc <= SYSUTCDATETIME() THEN 1 ELSE 0 END
        FROM dbo.BackgroundJobSchedule
        WHERE JobName = @jobName;
        """;

    private readonly Func<DbConnection> connectionFactory;
    private readonly int leaseSeconds;

    public SqlJobScheduleStore(Func<DbConnection> connectionFactory, TimeSpan leaseDuration)
    {
        if (leaseDuration < TimeSpan.FromSeconds(1))
        {
            throw new ArgumentOutOfRangeException(nameof(leaseDuration), "Use a lease of at least one second.");
        }

        this.connectionFactory = connectionFactory ?? throw new ArgumentNullException(nameof(connectionFactory));
        leaseSeconds = (int)Math.Ceiling(leaseDuration.TotalSeconds);
        LeaseDuration = TimeSpan.FromSeconds(leaseSeconds);
    }

    public TimeSpan LeaseDuration { get; }

    /// <summary>Unique per process start, so a restarted process never mistakes an old claim for its own.</summary>
    public string Holder { get; } = $"{Environment.MachineName}/{Environment.ProcessId}/{Guid.NewGuid():N}";

    public async Task<IJobClaim?> TryClaimDueAsync(string jobName, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = Command(connection, ClaimSql, jobName, generation: null);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var occurrence = new JobOccurrence(jobName, DateTime.SpecifyKind(reader.GetDateTime(1), DateTimeKind.Utc), reader.GetInt64(0));
        return new Claim(this, occurrence);
    }

    public async Task<bool> IsDueAsync(string jobName, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = IsDueSql;
        Add(command, "@jobName", DbType.String, jobName);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture) == 1;
    }

    private async Task<int> RowsAsync(string sql, JobOccurrence occurrence, int? retrySeconds, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = Command(connection, sql, occurrence.JobName, occurrence.FencingToken);
        if (retrySeconds is not null)
        {
            Add(command, "@retrySeconds", DbType.Int32, retrySeconds.Value);
        }

        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<DbConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = connectionFactory();
        try
        {
            await connection.OpenAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private DbCommand Command(DbConnection connection, string sql, string jobName, long? generation)
    {
        var command = connection.CreateCommand();
        command.CommandText = sql;
        Add(command, "@jobName", DbType.String, jobName);
        Add(command, "@holder", DbType.String, Holder);
        Add(command, "@leaseSeconds", DbType.Int32, leaseSeconds);
        if (generation is not null)
        {
            Add(command, "@generation", DbType.Int64, generation.Value);
        }

        return command;
    }

    private static void Add(DbCommand command, string name, DbType type, object value)
    {
        var parameter = command.CreateParameter();
        parameter.ParameterName = name;
        parameter.DbType = type;
        parameter.Value = value;
        command.Parameters.Add(parameter);
    }

    private sealed class Claim(SqlJobScheduleStore store, JobOccurrence occurrence) : IJobClaim
    {
        private bool recordAttempted;

        public JobOccurrence Occurrence => occurrence;

        public async Task<bool> RenewAsync(CancellationToken cancellationToken)
            => await store.RowsAsync(RenewSql, occurrence, retrySeconds: null, cancellationToken) == 1;

        public Task<bool> CompleteAsync(CancellationToken cancellationToken)
            => RecordAsync(CompleteSql, retrySeconds: null, cancellationToken);

        public Task<bool> FailAsync(TimeSpan retryAfter, CancellationToken cancellationToken)
            => RecordAsync(FailSql, (int)Math.Ceiling(retryAfter.TotalSeconds), cancellationToken);

        public async ValueTask DisposeAsync()
        {
            if (recordAttempted)
            {
                return;
            }

            try
            {
                await store.RowsAsync(ReleaseSql, occurrence, retrySeconds: null, CancellationToken.None);
            }
            catch (DbException)
            {
                // Releasing early only shortens the wait; lease expiry is what guarantees recovery.
            }
        }

        private async Task<bool> RecordAsync(string sql, int? retrySeconds, CancellationToken cancellationToken)
        {
            // Once recording has been attempted, never release: if the attempt failed midway, releasing would
            // make the occurrence claimable at once, skipping the retry delay or repeating a completed run.
            // The lease then expires on its own.
            recordAttempted = true;
            return await store.RowsAsync(sql, occurrence, retrySeconds, cancellationToken) == 1;
        }
    }
}
