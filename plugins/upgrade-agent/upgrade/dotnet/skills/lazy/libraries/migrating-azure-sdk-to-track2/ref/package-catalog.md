# The Azure package catalog

How to resolve any Azure .NET package against Azure's published release data, and where that data
misleads.

## Contents

- [Source of truth](#source-of-truth)
- [Fields](#fields)
- [Lookup rules](#lookup-rules)
- [Reading an NA replacement](#reading-an-na-replacement)
- [Querying the catalog](#querying-the-catalog)
- [Where `Replace` needs judgement](#where-replace-needs-judgement)
- [Offline naming heuristics](#offline-naming-heuristics)
- [Track 1 support packages](#track-1-support-packages)
- [The compat type usually means a rename](#the-compat-type-usually-means-a-rename)
- [Families that need a human decision](#families-that-need-a-human-decision)
- [Reporting table](#reporting-table)

## Source of truth

```text
https://raw.githubusercontent.com/Azure/azure-sdk/main/_data/releases/latest/dotnet-packages.csv
```

One CSV backs every published Azure SDK release page. The public deprecation list at
`https://azure.github.io/azure-sdk/releases/deprecated/index.html` is the same file filtered on
`Support == deprecated`, so there is no separate feed to fetch.

Counts in this file were measured against that CSV and are given to calibrate expectations, not to be
trusted as current. Re-derive anything you depend on.

## Fields

| Field | Meaning | How to use it |
|---|---|---|
| `Package` | NuGet package ID | Match exactly. Prefix matching produces false positives. |
| `Type` | `client`, `mgmt`, `compat`, `tool`, `functions` | Describes the *legacy* package. A default, not a routing decision — route on the resolved replacement. |
| `Support` | Support state | `deprecated` is the authoritative signal. Blank means unclassified, not healthy — most rows are blank. |
| `EOLDate` | End of life | Report it. It is what makes the migration urgent. |
| `Replace` | Suggested replacement package(s) | A starting point. Comma-separated when a package splits. |
| `ReplaceGuide` | Migration guide URL | Fetch before rewriting — but confirm it is for .NET (see below). |
| `Notes` | Free text | **Almost always empty** — 4 of 385 deprecated rows have any. Read it when present; do not build a step around it. |
| `ServiceName` | Azure service family | Groups related packages that should migrate together. |
| `VersionGA` | Newest stable version | Never use for pinning — it ignores the project's target framework. Use `get_supported_package_version`. |

## Lookup rules

1. Match on the exact `Package` value.
2. `Support == deprecated` means migrate. A blank or `NA` `Replace` narrows *how*, not *whether*.
3. **Resolve the replacement too.** Some `Replace` values name packages that are themselves
   deprecated, so following the column blindly ports code onto a dead target. Measured instances:

   | Deprecated package | `Replace` names | which is also deprecated |
   |---|---|---|
   | `Microsoft.Azure.Management.AppPlatform` | `Azure.ResourceManager.AppPlatform` | yes |
   | `Microsoft.Azure.Management.ChangeAnalysis` | `Azure.ResourceManager.ChangeAnalysis` | yes |
   | `Microsoft.Azure.Management.HybridData` | `Azure.ResourceManager.HybridData` | yes |
   | `Microsoft.Azure.Management.Media` | `Azure.ResourceManager.Media` | yes |
   | `Microsoft.Azure.Management.MixedReality` | `Azure.ResourceManager.MixedReality` | yes |
   | `Microsoft.WindowsAzure.Mobile.Service.ResourceBroker` | *itself* | yes |

   When the replacement is also deprecated, the service is retiring. Report it; do not migrate.
   `Microsoft.WindowsAzure.ConfigurationManager` is the two-hop case: its note points at
   `Microsoft.Azure.ConfigurationManager`, which is also deprecated with no successor.
4. **An `Azure.*` prefix is not proof of health.** Roughly 29 `Azure.*` packages are deprecated —
   13 under `Azure.ResourceManager.*` and 16 elsewhere (`Azure.Monitor.Query`,
   `Azure.MixedReality.*`, `Azure.Communication.CallingServer`, `Azure.Analytics.Purview.*`,
   `Azure.Media.VideoAnalyzer.Edge`, `Azure.Identity.BrokeredAuthentication`, and others). These are
   Track 2 packages whose *service* retired. Check every package, including modern-looking ones.
5. When `Replace` lists several packages, the code decides which are needed. Do not add them all.
6. When the catalog and prior knowledge disagree, the catalog and its guide win — **on status and on
   which package replaces which.** Their behavioral claims (defaults, semantics, encodings) carry no
   such authority and must be verified against the package itself; see
   [behavior-audit.md](behavior-audit.md).

## Reading an NA replacement

`NA` means the catalog cannot name a single successor package. It does **not** mean the service was
retired. Of 385 deprecated packages, about 152 have `NA` or blank in `Replace`; 19 of those still
carry a real `ReplaceGuide`. Four distinct situations hide behind `NA`, and only the guide separates
them:

- **A one-to-many split.** `Azure.Monitor.Query` has `Replace = NA`, and its guide directs logs code
  to `Azure.Monitor.Query.Logs`, metrics code to `Azure.Monitor.Query.Metrics`, and
  `MetricsQueryClient` to `Azure.ResourceManager.Monitor`. This is a normal migration.
- **A successor named only in prose.** `Azure.Communication.CallingServer` points at the
  `Azure.Communication.CallAutomation` README, and its `Notes` field says so outright.
- **A guide for a different language.** The eight C++ storage packages (`wastorage`,
  `wastorage.redist`, `wastorage.symbols`, `wastorage.v120`, `wastorage.v140`,
  `Microsoft.Azure.Storage.CPP`, `.CPP.v120`, `.CPP.v140`) are typed `client` in this .NET catalog and
  their `ReplaceGuide` points at the **azure-sdk-for-cpp** migration guide. They are not .NET
  packages. If one appears in a .NET project it is a native dependency; report it and do not follow
  the guide.
- **A genuine retirement.** `Azure.ResourceManager.Media` points at the Media Services retirement
  notice; `Azure.ResourceManager.AppPlatform` at the Spring Apps retirement notice.

Only the last is a stop-and-report.

**The stop-and-report bucket is large, not exceptional.** About 133 of the 385 deprecated packages
have neither a replacement nor a guide — roughly 70 `mgmt`, 55 `client`, 8 `compat`. Azure Stack
admin packages, the entire Bing Search family, Mobile Services, and Caching all live here. Treat
producing a clean list of these as a first-class output of the migration, not as a failure.

## Querying the catalog

Fetch once, parse once, reuse. The file is around 1,200 rows, so re-downloading per package is slow
and pointless.

```powershell
$uri = 'https://raw.githubusercontent.com/Azure/azure-sdk/main/_data/releases/latest/dotnet-packages.csv'
$catalog = Invoke-RestMethod $uri | ConvertFrom-Csv

# status of one package
$catalog | Where-Object Package -eq 'Microsoft.Azure.ServiceBus' |
    Select-Object Package, Type, Support, EOLDate, Replace, ReplaceGuide, Notes

# every deprecated package the solution references, with the replacement's own status
$referenced = @('WindowsAzure.Storage', 'Microsoft.Azure.KeyVault')
foreach ($p in $referenced) {
    $row = $catalog | Where-Object Package -eq $p
    foreach ($t in ($row.Replace -split ',')) {
        $t = $t.Trim()
        if ($t -and $t -ne 'NA') {
            $target = $catalog | Where-Object Package -eq $t
            '{0} -> {1} (target support: {2})' -f $p, $t, $target.Support
        }
    }
}
```

## Where `Replace` needs judgement

The column is generated per package, so it cannot express "it depends what your code uses".

| Package | Catalog says | Use instead |
|---|---|---|
| `WindowsAzure.Storage` | `Azure.Storage.Common` | Split by usage: `Azure.Storage.Blobs`, `Azure.Storage.Queues`, `Azure.Storage.Files.Shares`, `Azure.Data.Tables`. `Azure.Storage.Common` is a shared dependency, not a client library. |
| `Microsoft.Azure.Storage.Common` | `Azure.Storage.Common` | Same — resolve from the service-specific packages the code needs. |
| `Microsoft.Azure.KeyVault` | three Key Vault packages | Add only the ones used: `.Secrets`, `.Keys`, `.Certificates`. |
| `Microsoft.Azure.Management.Fluent` | `Azure.ResourceManager` | That is the core only. Add one `Azure.ResourceManager.<Provider>` package per resource provider the code touches. |
| `Microsoft.Azure.EventHubs.Processor` | `Azure.Messaging.EventHubs.Processor` | Also needs `Azure.Messaging.EventHubs`. Legacy checkpoints are not directly compatible; plan checkpoint migration and cutover as described below. |
| `Microsoft.Azure.ServiceBus.EventProcessorHost` | `Azure.Messaging.EventHubs.Processor` | An Event Hubs package despite the Service Bus name. Its legacy checkpoints also need an explicit migration/cutover plan; do not assume the new processor can read them. |
| `Microsoft.Azure.DocumentDB` | `Microsoft.Azure.Cosmos` | The target keeps the `Microsoft.Azure.*` prefix and is current; no `Azure.*` equivalent exists. Hand this to `migrating-documentdb-to-cosmos`. |
| `Microsoft.Azure.Graph.RBAC`, `Microsoft.Azure.Management.Graph.RBAC.Fluent` | `Microsoft.Graph` | A different API with a different permission model. A rewrite, not a package swap. |
| `Microsoft.Hadoop.Client` | `Azure.ResourceManager.HDInsight` | Typed `client` but replaces with a management package. Route on the replacement. |

For either legacy EventProcessorHost generation, inspect the checkpoint provider and follow the
[official checkpoint migration guidance](https://github.com/Azure/azure-sdk-for-net/blob/Azure.Messaging.EventHubs_5.12.2/sdk/eventhub/Azure.Messaging.EventHubs/MigrationGuide.md#migrating-eventprocessorhost-checkpoints).
It describes converting per-partition progress into the target blob names and metadata. Coordinate
cutover so progress does not change during conversion. Without a usable checkpoint, the new processor
uses its starting position: replaying retained events or skipping earlier events if a later position
was configured. Report and obtain approval for any reset or changed starting position; do not make
reset the default migration strategy.

## Offline naming heuristics

Use only when the catalog cannot be reached, and label the result provisional.

| Legacy pattern | Modern pattern |
|---|---|
| `Microsoft.Azure.Management.<X>` | `Azure.ResourceManager.<X>` |
| `Microsoft.Azure.Management.<X>.Fluent` | `Azure.ResourceManager.<X>` — Fluent has no separate target |
| `Microsoft.WindowsAzure.Management.<X>` | `Azure.ResourceManager.<X>` |
| `Microsoft.Azure.<Service>` (messaging) | `Azure.Messaging.<Service>` |
| `Microsoft.Azure.Storage.<X>` | `Azure.Storage.<X>` (note `Queue` becomes `Queues`) |
| `Microsoft.Azure.KeyVault*` | `Azure.Security.KeyVault.<X>`, split by resource type |
| `Microsoft.Azure.CognitiveServices.<Area>.<X>` | `Azure.AI.<something>` — rarely mechanical |

**The pattern is a last resort, not a resolver.** Provider renames, core-package targets and splits
break simple prefix substitution. Concrete examples:

| Legacy | Actual replacement |
|---|---|
| `Microsoft.Azure.Management.WebSites` | `Azure.ResourceManager.AppService` |
| `Microsoft.Azure.Management.Scheduler` | `Azure.ResourceManager.Logic` |
| `Microsoft.Azure.Management.EventHub` | `Azure.ResourceManager.EventHubs` |
| `Microsoft.Azure.Management.LocationBasedServices` | `Azure.ResourceManager.Maps` |
| `Microsoft.Azure.Management.AzureStackHCI` | `Azure.ResourceManager.Hci` |
| `Microsoft.Azure.Management.EdgeGateway` | `Azure.ResourceManager.DataBoxEdge` |
| `Microsoft.Azure.Management.BatchAI` | `Azure.ResourceManager.Batch` |
| `Microsoft.Azure.Management.ManagementGroups`, `...ResourceManager` | `Azure.ResourceManager` (core) |
| `Microsoft.Azure.Management.SiteRecovery` | `Azure.ResourceManager.RecoveryServicesSiteRecovery` |
| `Microsoft.Azure.Management.Insights` | `Azure.ResourceManager.Monitor` |

Always confirm a guessed package exists on NuGet before writing it into a project file.

## Track 1 support packages

These carry no Azure functionality. They exist to support Track 1 packages and are removed once the
last consumer is gone.

- `Microsoft.Rest.ClientRuntime`
- `Microsoft.Rest.ClientRuntime.Azure`
- `Microsoft.Rest.ClientRuntime.Azure.Authentication`
- `Microsoft.Rest.ClientRuntime.Azure.TestFramework` — test infrastructure, see below
- `Microsoft.Azure.Common`, `Microsoft.Azure.Common.Authentication`
- `Microsoft.WindowsAzure.Common`, `.Common.Dependencies`, `.Common.Tracing.Etw`,
  `.Common.Tracing.Log4Net`
- `Microsoft.Azure.ConfigurationManager`
- `Microsoft.Azure.Services.AppAuthentication` — superseded by `Azure.Identity`
- `Microsoft.IdentityModel.Clients.ActiveDirectory` (ADAL) — superseded by `Azure.Identity`/MSAL

The `Microsoft.Rest.ClientRuntime`, `.Azure`, and `.Azure.Authentication` packages plus
`Microsoft.Azure.Common` show as `active` in the catalog — that reflects the runtime still being
serviced, not the legacy packages that depend on it. `Microsoft.Rest.ClientRuntime.Azure.TestFramework`
is `deprecated` with `Replace = NA`. The `Microsoft.WindowsAzure.Common*` family is the older
generation of the same thing and is also `deprecated` with `Replace = NA`. ADAL is not in the catalog
at all — it is not an Azure SDK package — so its absence is not evidence of anything.

**Test-infrastructure packages have no Track 2 successor.**
`Microsoft.Rest.ClientRuntime.Azure.TestFramework` supported the Track 1 record/replay harness; Track 2
libraries use the Azure SDK's own test framework, which is not a drop-in replacement. Test projects
built on it need their harness reworked, which is a separate piece of work from the production
migration. Report it rather than folding it in silently.

`Microsoft.Azure.ConfigurationManager` is `compat`-typed with `Replace = NA` because
`CloudConfigurationManager` was a Cloud Services concept with no successor. Move that configuration
to `IConfiguration` or environment variables.

## The compat type usually means a rename

`compat` rows are mostly repackagings *within* the same generation, so the Track 2 contract does not
apply to them and there is no client shape to rewrite:

- `Microsoft.Azure.Jobs` → `Microsoft.Azure.WebJobs`, `.Jobs.Core` → `.WebJobs.Core`,
  `.Jobs.ServiceBus` → `.WebJobs.Extensions.ServiceBus`
- `Microsoft.Azure.WebJobs.CosmosDb.Mongo` and `.Extensions.CosmosDb.Mongo` →
  `.Extensions.AzureCosmosDb.Mongo`
- `Microsoft.OpenTelemetry.Exporter.AzureMonitor` → `Azure.Monitor.OpenTelemetry.Exporter`, which its
  `Notes` field records as a rename before GA

The remaining `compat` rows are retirements (`Microsoft.Azure.WebJobs.Script*`,
`.Extensions.ApiHub`, `.Extensions.WebHooks`, both `ConfigurationManager` packages). At least one is a
real track migration (`Microsoft.Azure.Storage.Common` → `Azure.Storage.Common`), so confirm which
kind you have rather than assuming the type code decides it.

## Families that need a human decision

Report these with their EOL date and any guide URL rather than migrating them.

- Any package where `Replace` and `ReplaceGuide` are both `NA` or blank.
- Retired services: Media Services, Video Analyzer, StorSimple, RemoteApp, Mixed Reality, Remote
  Rendering, Mobile Services, Azure Caching, and the entire Bing Search family (which left Azure
  rather than moving to a new package).
- Azure Stack admin packages (`Microsoft.AzureStack.Management.*.Admin`) and
  `Microsoft.Azure.Management.Profiles.hybrid_*`, which target API-version profiles Track 2 does not
  model the same way.
- Cognitive Services packages whose successor is a redesigned service rather than a renamed library —
  LUIS, QnA Maker, Personalizer, and Content Moderator all changed shape and carry their own
  service-level retirement guidance.
- Preview-only replacements: when the replacement's `VersionGA` is blank but `VersionPreview` is set,
  say so and let the user decide.

**`NA` is scoped to the Azure SDK.** It records that the Azure SDK team ships no successor, not that
none exists anywhere. Packages that merely integrate with Azure — SQL Server key-store providers,
logging sinks, OpenTelemetry exporters, third-party bindings — can have a successor shipped by
another team. `Microsoft.SqlServer.Management.AlwaysEncrypted.AzureKeyVaultProvider` is such a row:
`mgmt`-typed with `Replace = NA`, but the Always Encrypted key-store provider moved with the rest of
the SQL client stack rather than disappearing. Check NuGet and the package's project page before
reporting a dead end.

## Reporting table

Carry this through planning and re-verify every row during validation.

| Package | Type | Support | EOL | Replacement | Replacement status | Guide | Files to rewrite |
|---|---|---|---|---|---|---|---|
| `Microsoft.Azure.ServiceBus` | client | deprecated | 2026-09-30 | `Azure.Messaging.ServiceBus` | active | aka.ms/azsdk/net/migrate/sb | `Messaging/QueueSender.cs` |
| `Microsoft.Azure.Management.Media` | mgmt | deprecated | 2024-06-30 | `Azure.ResourceManager.Media` | **also deprecated** | retirement notice | none — report |
| `Azure.MixedReality.RemoteRendering` | client | deprecated | 2025-10-01 | none | n/a | none | manual decision |
