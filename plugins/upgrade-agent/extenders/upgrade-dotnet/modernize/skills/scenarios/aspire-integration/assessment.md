# Assessment Instructions (Phase 2)

Detailed instructions for SKILL.md Phase 2. Read completely before starting.

## Contents

- [Goal](#goal)
- [Entry Criteria](#entry-criteria)
- [Step 1: TFM Compatibility](#step-1-tfm-compatibility)
- [Step 2: Map Inter-Service Communication](#step-2-map-inter-service-communication)
- [Step 3: Present Assessment Summary](#step-3-present-assessment-summary)
- [Edge Cases](#edge-cases)
- [Checklist Before Moving to Phase 3](#checklist-before-moving-to-phase-3)

This file covers two required steps:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | TFM Compatibility | Reuse results from Phase 0.1 — no re-scan |
| 2 | Inter-Service Communication Mapping | Unique value-add — produces the context graph for aspireify |

---

## Goal

Produce two outputs that feed into Phase 3 (user config) and the aspireify delegation in Phase 5 Task 02:

1. **TFM-compatible project list** — which projects aspireify should include
2. **Inter-service communication graph** — which services talk to which, so aspireify can wire `WithReference()` and `WaitFor()` correctly

Infrastructure detection (databases, caches, messaging, etc.) is **owned entirely by aspireify** via live `aspire docs search` and `aspire list integrations`. Do not duplicate that work here.

## Entry Criteria

- Phase 0 and Phase 1 complete
- On correct working branch
- Aspire CLI present and skills installed

---

## Step 1: TFM Compatibility

Reuse the TFM classification from Phase 0.1. No re-scan needed.

Carry forward:
- `compatible_projects[]` — full paths and TFMs
- `incompatible_projects[]` — full paths and TFMs (skip list for aspireify)

**Compatible TFMs:** `net8.0`, `net9.0`, `net10.0`, any `net{X}.0` where X ≥ 8. Multi-targeted with at least one compatible TFM = compatible.

**Incompatible TFMs:** `net4*`, `netstandard*`, `netcoreapp*`, `net5.0`, `net6.0`, `net7.0`.

---

## Step 2: Map Inter-Service Communication

Scan all **compatible** projects only. This is read-only file analysis — do not run any processes.

### 2.1 HTTP Client Detection

Search for:
- `AddHttpClient<T>()` or `AddHttpClient("name")` → extract the registered base URL or named client target
- `IHttpClientFactory` usage → trace to `appsettings.json` or `appsettings.Development.json` base addresses
- `HttpClient` constructor calls with explicit `BaseAddress`
- Hardcoded URLs in code: `http://localhost:{port}`, `https://localhost:{port}`, `http://{service-name}:{port}`
- Base address config in `appsettings.json`: look for keys named `*BaseUrl*`, `*ServiceUrl*`, `*Endpoint*`, `*Host*`

### 2.2 gRPC Client Detection

Search for:
- `AddGrpcClient<T>()` → extract service address from config or constructor
- `GrpcChannel.ForAddress()` calls → extract address argument
- `.proto` files → note service names for relationship mapping

### 2.3 Message Bus Communication

Search for:
- MassTransit: `UsingRabbitMq()`, `UsingAzureServiceBus()`, `UsingKafka()` — extract endpoint config
- NServiceBus: endpoint name configuration
- Publisher/consumer pairs sharing the same queue/topic name across projects
- Shared `Azure.Messaging.ServiceBus.ServiceBusClient` configuration

### 2.4 Shared Database Access

Search for projects that reference the same connection string name or database name:
- Same key in `appsettings.json` across multiple projects (e.g., `"ConnectionStrings:MyDb"`)
- Same `<UserSecretsId>` referencing the same database URL
- Shared class library with database context used by multiple entry-point projects

### 2.5 Build the Communication Graph

For each compatible project, document:
- **Outbound**: services/resources it calls (HTTP URL, gRPC address, queue name, DB name)
- **Inbound**: services that call it (derived from other projects' outbound)
- **Shared resources**: databases/caches accessed by more than one project

Format as plain text for inclusion in the aspireify delegation prompt:

```
Inter-service communication graph:

Direct calls:
- {project-A} --HTTP--> {project-B}: AddHttpClient base URL "http://localhost:5001"
- {project-C} --gRPC--> {project-D}: GrpcChannel.ForAddress("http://localhost:5002")

Shared resources:
- shared DB (ConnectionStrings:MyDb): {project-A}, {project-B} reference the connection string
- message bus queue "orders": {project-E} (producer), {project-F} (consumer) both use the queue

Incompatible projects (excluded from Aspire):
- {project-X} ({tfm}) — will not appear in aspireify's project list
```

If static analysis surfaces no inter-service communication, omit the section entirely. Do not assert "no communication detected" — absence of evidence in source code is not proof, and aspireify should not consume an unverifiable negative claim.

---

## Step 3: Present Assessment Summary

Present before moving to Phase 3:

> **Assessment Complete**
>
> - **{N} compatible projects**: {list with TFMs}
> - **{M} incompatible projects** (will be skipped): {list}
> - **Inter-service links**: {include this bullet only if Step 2 surfaced any links — e.g., "frontend → api (HTTP), api → worker (message bus)"; otherwise omit the bullet}
>
> Infrastructure resources (databases, caches, messaging) will be detected and integrated by the aspireify skill during execution.

Wait for user to confirm before proceeding to Phase 3.

---

## Edge Cases

### No Compatible Projects

Handled by Phase 0.1 hard stop — this case should not reach Phase 2.

### No Entry Point Projects (all class libraries)

If all compatible projects are class libraries (`<OutputType>Library</OutputType>` or default):

<response_template>
ℹ️ **No Entry Point Projects Found**

All compatible projects are class libraries. Aspire orchestrates runnable applications (Web APIs, Workers, Console apps, etc.).

**Options:**
1. Create a minimal AppHost that orchestrates infrastructure only (databases, caches, brokers)
2. Identify which libraries are actually entry points (miscategorized?)
3. Cancel this scenario
</response_template>

### Desktop-Only Solution

All entry points are desktop apps (WPF, WinForms, MAUI, Avalonia). **This is valid.** Desktop apps are first-class Aspire citizens — Aspire launches them, shows them in the dashboard, and manages their infrastructure.

⚠️ **Never refuse Aspire integration because a solution only has desktop apps.**

Note in the assessment summary: *"All projects are desktop apps — inner-loop only is recommended (desktop apps do not deploy to Azure)."*

### No Inter-Service Communication

Valid — note in the summary. aspireify will still wire each project to its infrastructure. No `WithReference`/`WaitFor` hints will be passed.

---

## Checklist Before Moving to Phase 3

- [ ] Compatible and incompatible projects identified (from Phase 0.1)
- [ ] Inter-service communication graph built (or noted as none)
- [ ] Assessment summary presented and user confirmed
