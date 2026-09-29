---
name: analyzing-cross-host-route-ownership
description: >
  Determines which URLs a partly migrated app is still served by the old .NET Framework host and
  which the new ASP.NET Core host already answers, by reading both projects and the YARP route
  table. Use when planning the next wave of a side-by-side migration, before deleting or moving a
  Framework route, or when deciding whether a route has finished migrating. Also triggers for
  "which routes still run on the old app", "what is the proxy forwarding", "is this route migrated
  yet", "what is safe to move next", "route inventory", "did we miss a route", "both apps seem to
  handle this URL", and "can I delete this Framework route yet".
metadata:
  traits: .NET|CSharp|DotNetCore
  discovery: lazy
---

# Cross-Host Route Ownership Analysis

In a side-by-side migration two hosts are live at once. The new ASP.NET Core host takes
the request first, serves what it has already migrated, and forwards the rest through YARP
to the still-running .NET Framework app. The question that governs every wave is which
URLs are on which side — and it cannot be answered by reading either project alone,
because the answer lives in the relationship between three things: the Framework route
table, the Core endpoint table, and the proxy configuration.

This skill covers reading that answer. It does not migrate routes
(**migrating-mvc-routing**) and does not create the proxy
(**scaffolding-yarp-proxy-project**).

This adds a machine-readable inventory and ownership/conflict analysis to the prose
baseline in **migrating-aspnet-framework-to-core/side-by-side.md**. Keep that baseline
for runtime comparison; the report does not replace it.

**Version 1 supports C# projects only.** Both inputs must be `.csproj` files. Visual Basic
and other project languages are not supported; do not interpret an unsupported project
as having no routes. Projects must be loadable through the current workspace. An unloaded
proxy is reported as unreadable, not scanned by guessing which files belong to it.

## Get the answer from the tool, not by reading route files

```
analyze_route_ownership(
  projectPath="{full path to the .NET Framework .csproj}",
  proxyProjectPath="{full path to the ASP.NET Core .csproj}"
)
```

Both paths must be absolute. `proxyProjectPath` is optional and omitting it changes the
question being asked: without it you get an inventory of the Framework routes with every
answer that depends on Core coverage reported as unknown — useful before the Core host
exists and misleading afterwards. **Supply it whenever the Core host exists.**

Do not answer ownership questions by reading `RouteConfig.cs` and `Program.cs` yourself.
Route templates that look equivalent frequently are not, and the differences are not
visible in the strings:

- A Framework route with `defaults: new { action = "Index" }` serves the bare prefix
  `/packages`. A Core route written `packages/{action}/{id?}` does not. The templates read
  almost identically and cover different URL sets.
- `IgnoreRoute` installs a `StopRoutingHandler`. It looks like a registered route and
  serves nothing.
- A route registered inside `if (config.EnableFeature)` may or may not exist at runtime,
  and the source does not say which.
- MVC and Web API/OData use separate ordering domains; OData shares the Web API collection.
  Core endpoint routing is another domain. There is no comparable global registration index.

The tool models these. A reading of the two files does not.

## The seven ownership states, and what each one licenses

Every route in the report carries exactly one `ownership` value. They are not degrees of
confidence — they are different findings, and they call for different actions.

| State | Meaning | What it licenses |
|-------|---------|------------------|
| `Terminated` | Static evidence covers this route's paths and methods on Core. | A deletion candidate, subject to every prerequisite in "Deleting a Framework route"; not unconditional permission. |
| `Forwarded` | The proxy forwards this route's URL space to the Framework app, or a Core handler for it forwards at least some requests (`kind: "Forwarder"`; read the handler before saying what it serves). | It is still live on the old host. Migrating it is a unit of work; deleting it is an outage. |
| `Partial` | Local coverage is incomplete or symbolic, or the proxy forwards only a slice. | **Not proven complete.** Inspect candidates and remaining traffic; this need not mean anything has migrated. |
| `Unclaimed` | The proxy was read, but no eligible local coverage or proven forwarding was found. | Investigate a possible routing gap; a Core fallback may still answer. This is not proof of a 404. |
| `Ignored` | An `IgnoreRoute` that provably registers, or a route an earlier one provably swallows. | A swallowed route never matches inbound and can go, subject to the preconditions in "Deleting a Framework route". The `IgnoreRoute` itself cannot — it is working, not redundant. |
| `Unknown` | Ownership could not be determined. | Read `unknownReason` and resolve it before acting. |
| `NotApplicable` | The route is on the Core host, so there is no Framework space for it to take over. | Nothing. Ownership is a question about Framework routes; filter these out before reasoning about coverage. |

`Partial` is the state that matters most, because it is the ordinary shape of a migration
in progress and the one that collapses if you only have "migrated" and "not migrated". A
broad Framework default route stays `Partial` for the whole middle of a migration: each
wave takes another slice of it, and it is not finished until the last one lands.

`Partial` arises two ways, and the difference is visible in `terminatedBy`:

- **`terminatedBy` is populated.** Core endpoints overlap this space but were not shown to
  cover all of it. Establish what they actually serve before deciding which traffic
  remains.
- **`terminatedBy` is empty.** No eligible local coverage was found; the proxy forwards only
  a slice. This proves neither migration nor that the remainder is unreachable: a Core
  fallback may still answer. Inspect the remaining paths and methods.

`residualForwarded` records whether a forwarder relates to this space. It does not prove
that every remaining URL or verb reaches Framework. `Terminated` clears it even when a forwarder
overlaps. For other verdicts, false means no related forwarding was found; inspect unresolved
gaps before deciding whether any remainder is unreachable.

**`Unknown` is a question, not a failure.** The `unknownReason` says what is missing:

- `NoProxySupplied` — re-run with `proxyProjectPath`.
- `ProxyUnreadable` — the Core project could not be read. Usually it does not build.
  Fix that first; the answer is not unavailable, it was never gathered.
- `ConditionalCoverage` — a registration that decides this route's coverage is gated on
  configuration or sits in a loop, so whether it registers is a deployment fact. This
  record's `predicate` gates only this route's own registration, so it answers the
  question in the first case below and not the second:
  - **This route is itself a gated `IgnoreRoute`** (`kind: "Ignore"`) — its own `predicate`
    holds the condition, and that is the whole finding.
  - **Otherwise a gated Core endpoint or YARP forwarder** decides the space, and nothing
    here points at it: it is deliberately left out of `terminatedBy`, because an unproven
    registration is not a coverage candidate. A `predicate` on this record does not fill
    that gap — a Framework route can be gated itself and still report this reason for a
    gated counterpart, so reading it answers the wrong question. Find the deciding
    registration in `routes`: the entries carrying `conditional: true` or
    `mayRegisterMultipleTimes: true` whose template reaches this route's URL space. A
    gate is in `predicate` there, but a non-null `predicate` is not a readable one: a
    loop records `mayRegisterMultipleTimes` beside an atom reading "loop at line N may
    not execute", and an activation path the tool could not follow records one of its
    own. Read `isOpaque` on the atoms — an opaque atom is the tool saying it could not
    evaluate the condition, not the condition itself. Where the gate is opaque or
    absent, the route stays undeletable — do not infer coverage from template shape.

  Then decide per environment and re-run.
- `UnevaluableConstraint` — match data on one side could not be evaluated, including
  constraints, defaults, or endpoint conventions. Read the linked unresolved entry.
- `OpaqueRegistrar` — something claims part of this space through an API the tool cannot
  see into. When `routes` holds a `Middleware` or `MiddlewareBranch` record, **load [ref/pipeline-code.md](ref/pipeline-code.md)**.
- `UnresolvedSymbol` — a template was not a compile-time constant, so the URL space it
  denotes is not knowable from the source.
- `ProxyPrecedence` — Core endpoints do cover this space, but a forwarder overlapping it
  is not known to lose endpoint selection to them, so the request may still reach
  Framework. Core orders endpoints by `Order` before template specificity, so a forwarder
  whose `Order` is lower than the local endpoint's wins however specific that endpoint is.
  Load [ref/endpoint-order.md](ref/endpoint-order.md) before interpreting conflicts or changing order.
  It distinguishes readable conventions, opaque overrides, and conflicts that disagree.

`terminatedBy` names covering endpoints on `Terminated`, but on `Partial` it can name
symbolic overlaps rather than a slice proven to have moved. On `Unknown` it names
overlapping **candidates** whose coverage could not be proven
— the shortlist to check, not a set of proven replacements. `ProxyPrecedence` is an
exception where coverage *was* proven and what answers first is in doubt. `OpaqueRegistrar`
from pipeline code may mean that or unproven candidates, and the reason alone does not say
which, so verify the list. Either way, an `Unknown`'s `terminatedBy` never licenses a deletion.

## How coverage is decided, and what `basis` tells you

Two fields describe the quality of a route's answer, and they answer different questions.

`precision` is about **reading the route**: how much of what the tool knows about this
registration came from bound symbols. It is set when the route is scanned, and it says
nothing about how its ownership was later decided.

- **`Enumerated`** — the scanner read a direct registration or controller/action values.
  On conventional routes, defaults can populate `controller` and `action` even while those
  tokens remain free. Thus `precision: "Enumerated"` does not prove a concrete URL space.
  Read `template` and `basis` rather than treating these fields as expanded actions.
- **`Subsumption`** — the scanner represents the registration by its template, including
  conventional Core registrations. This does not determine its eventual coverage basis.
- **`SyntaxOnly`** — symbols did not bind at all and a bounded set of known registration
  shapes was matched textually. Treat findings at this precision as leads.

`basis` is about **deciding ownership**, and it is the field to read before acting on a verdict.

- **`Enumerated`** — conventional routes were expanded against the actions that actually exist, and
  coverage was settled over the URLs they really serve. A conventional route such as
  `{controller}/{action}/{id?}` is expanded by pairing each controller/action reachable
  through it with the URL the route builds for it, carrying the action's HTTP-method
  constraints along. This is the strongest answer the tool produces, and the only one
  under which a conventional Core route can contribute proven coverage. A directly mapped
  Core endpoint can cover a Framework template without conventional Core expansion.
- **`Symbolic`** — coverage was decided by comparing template shapes. A shape containing
  another shape is real evidence but weaker: it says the Core template *could* serve these
  URLs, not that any action behind it does.

The two can disagree, and a route with `precision: "Enumerated"` and `basis: "Symbolic"`
is the ordinary case: the registration was read exactly, and the other host's was not.

Expansion is read two ways on purpose, and the difference is what keeps a destructive
verdict honest. Deciding a route's *own* URL space takes every action it might dispatch
to; deciding whether Core *covers* it takes only the actions Core certainly dispatches to.
A pairing the expander is unsure of therefore widens the space to be covered and never
counts towards covering it. An action is uncertain when it carries host metadata the tool
cannot evaluate, when its name can be rewritten by configuration, or when two overloads
collapse onto one route value and the framework would have to break the tie.

Enumeration can also settle an overlap in the negative, and this is the one case where a
route reports *less* than the templates suggest. Where both sides were enumerated and not
one URL this route really serves is answered on Core, the overlap the templates implied is
known to be illusory — `nothing/here` fits the shape of `{controller}/{action}` without
being a URL any controller behind it produces. The Core route is then dropped from
`terminatedBy` rather than reported as partial coverage, because sending someone to
reconcile a slice that never moved costs them the same afternoon a real one would. This
retraction is withheld unless every Core registration that could reach the space stated
its URLs; where one did not, absence of evidence is not read as evidence of absence.

Enumeration is skipped — leaving `basis: "Symbolic"` — for any of these reasons:

- The action inventory could not be built at all: the project did not bind, or the actions
  behind a route are selected by something outside the compile-time reference set.
- The route is not conventional. An attribute route already states a literal URL and needs
  no expansion; a fallback, an ignore rule or a middleware branch has no action set.
- Its `{controller}` token carries a constraint, or shares a segment with literal text
  (`{controller}-legacy`), so the values it admits are not the controller names.
- Its match data contains something the tool cannot read.
- The expansion would exceed the tool's endpoint ceiling. A route on a large project can
  pair with thousands of actions, and past that point the expansion is abandoned rather
  than truncated — a truncated one would look like a complete, smaller route.

Nothing is lost when enumeration is skipped except sharpness: the template comparison still
runs, and a route it cannot settle lands in `Partial` or `Unknown` rather than being claimed.

### Matching and residual coverage

Framework defaults make the named parameters optional, so `{id}` with
`id = UrlParameter.Optional` is compared with Core `{id?}`. Inline defaults also confer
optionality, while controller/action/area default values determine which shorter aliases
exist. Literal path comparisons ignore case; constraint arguments, including regex text,
retain their case. Opaque constraints and ambiguous mixed segments cannot prove inclusion.

Where enumeration is available, residual coverage excludes endpoints fully claimed by
provably earlier registrations on the same Framework surface. A provably earlier ignore
covering the entire route yields `Ignored`. Partial or undecidable overlaps are not
generally subtracted. Conditional registrations, loops, and registrations in different
method bodies can leave ordering uncertain. Registration indices are stable inventory
order, not unconditional proof of runtime order.

An intersection supplies a coverage candidate, not a `Terminated` verdict. That verdict
requires inclusion of the whole relevant space, including shorter aliases and HTTP methods.
On Core, lower `Order` is compared **before** template precedence; for equal order, literals
outrank parameters and catch-alls. Authorization runs after endpoint selection: a local
401/403 does not fall through to YARP. Middleware runs earlier: see `OpaqueRegistrar`.

## Read `unresolved` before you trust `routes`

The report has a second array. `unresolved` lists registrations the tool could see but
could not interpret, and each entry names a place where the inventory is incomplete.
**A report with entries here is not a clean bill of health**, and the states above are
only as complete as this list is empty.

The reasons that change what you should do:

- `ConfigDrivenGating` — the proxy calls `MapReverseProxy()` but its configured route
  table is empty, or nothing here proves that table is what the proxy loads, or a
  route's registration depends on runtime configuration. The third case is the one that
  looks wired up: a `ReverseProxy` section and a `MapReverseProxy()` call are both
  present, but no `LoadFromConfig(...)` was shown to bind that section, so the running
  proxy may take its routes from somewhere else entirely. Those routes are reported as
  conditional rather than dead — the proxy is live and may well forward them. What it
  forwards is a deployment fact that is not in the repository. Ask, or read the deployed
  configuration.
- `MalformedSource` — a project could not be loaded, a proxy directory could not be listed,
  a configuration file could not be read, or a route template or configuration file could
  not be parsed. Read the entry's `source`, `description`, and `proxyStatus`.
  If the Framework project did not load, `proxyStatus` is `NotEvaluated`: neither host was
  inventoried, even if a proxy path was supplied. Do not infer unaffected scope from the
  reason alone.
- `UnsupportedRegistrationApi` — a registration form the tool does not model, or a method
  it cannot read being handed the route collection. The second is the common one: a
  registrar that lives in a referenced package has no source to follow, so whatever it
  adds is invisible. Read it yourself and treat that URL space as undetermined.
- `AttributeRoutingNotEnabled` — controllers carry route attributes but nothing calls
  `MapMvcAttributeRoutes()` or `MapHttpAttributeRoutes()`, or on the Core side none of
  `MapControllers()`, `MapControllerRoute()`, `MapDefaultControllerRoute()` or
  `MapAreaControllerRoute()`. Those attributes are inert; a plan that migrates them as
  live routes is migrating nothing.
- `UnresolvedSymbol` — a template, default, or other required value could not be read.
  A registration may be missing entirely or retained with incomplete match data; inspect
  its affected IDs rather than assuming every such entry describes a dropped route.
- `UnevaluableConstraint` — a registration carries a constraint the tool cannot reason
  about, so the URL space in `routes` is an upper bound on what it really matches.
- `UnresolvedRedirectTarget` — a `Redirect(...)` was found but what it redirects to could
  not be proved. Retiring the destination silently breaks the redirect, so find it before
  planning either one. Where the target *was* proved there is no `unresolved` entry at
  all: the redirect route carries `targetResolution: "Single"` and names its destination
  in `redirectTargetIds`, which is how you check whether a route you are about to delete
  is something else's destination.
- `IndeterminateLoop` — a registration sits inside a loop, so how many routes it adds and
  where they sit in a first-match-wins collection are not knowable from the source.
  Ordering for that surface is approximate, which weakens every shadowing claim in it.
- `OpaqueRegistrar` — part of the URL space is claimed through an API the tool cannot see
  into, such as Core pipeline code (**load [ref/pipeline-code.md](ref/pipeline-code.md)**). On the
  Framework side it also covers a registration helper of your own that takes both the
  template and the route collection as parameters: the URL is its callers' to decide, and
  call sites are followed only for helpers named `MapRoute`, `MapPageRoute`, `IgnoreRoute`
  or `MapHttpRoute`, so any other name yields this entry naming the method instead of a
  route in `routes`. A helper whose template resolves to a compile-time constant is read
  normally whatever it is called; one that takes the template but reaches the collection
  some other way lands in `UnresolvedSymbol` instead, naming the invoked API rather than
  the helper. Open the named method and treat the URLs it adds as undetermined.

## `conflicts` is the third array, and it is not optional reading

Two registrations can both be live and still disagree about who answers a URL.
`conflicts` names those pairs in `participantIds`, alongside the `orderScope` the
disagreement lives in and `evidence` in plain words.

| `class` | What it means |
|---------|---------------|
| `LocalVersusCatchAll` | Three shapes, told apart by who is named in `participantIds`. **Two Core routes** — a local *catch-all* and the proxy catch-all cover the same space. Registration order does not decide this: Core compares lower numeric `Order` first, and where `Order`, precedence and selection metadata all tie there is no winner at all — the request fails with `AmbiguousMatchException`. Read `evidence` for which of the two this is. **A non-catch-all Core endpoint and the proxy catch-all** — reported whenever the local endpoint does not *provably* win. Core compares lower numeric `Order` before template precedence, so a more specific local template does not automatically beat the catch-all: it wins only at a lower `Order`, or at an equal `Order` where its precedence is higher. Where the relative `Order` cannot be established, the conflict is reported rather than assumed away. **A Framework route and a Core fallback** (`MapFallbackToFile` and friends) — informational. A fallback sits at the lowest precedence and answers only what matches nothing else, so it never displaces a real endpoint and is not evidence of migration. |
| `LocalVersusLocal` | Two registrations on one host may compete, and the two hosts fail differently. **Two Framework registrations** — source order, a shared HTTP method and containing templates are not proof of runtime shadowing: inspect activation, execution order and full method coverage, since the first match wins and the later route is simply never reached. **Two Core endpoints** — everything this analysis can read ties. Both serve a URL named in `evidence` at the same `Order` for a shared method, with equal precedence and equal constraints, and Core requires a unique winner, so the request throws `AmbiguousMatchException` rather than falling through to either. What decides it is endpoint *selection*, and this analysis reads only method and route constraints, not the whole of it: a `RequireHost` or `[Host]`, a `[Consumes]` content type, or any custom `IEndpointSelectorPolicy` separates the pair at runtime and is invisible here. Check the two registrations for a separator before treating it as broken — but treat it as a live failure until you have found one, because the tie is real everywhere this analysis can see. It is reported only where the shared URL was enumerated. |
| `ProxyVersusLocal` | An explicit proxy route and a local Core endpoint both claim the space. Compare `Order` first, then template precedence for equal order. Do not assume the local endpoint wins: requests may still forward to Framework, or a tie may fail as ambiguous. Read the conflict evidence before treating the local endpoint as the one serving the URL. |

A `LocalVersusLocal` entry deserves investigation, not automatic exclusion from a wave.
Its `evidence` distinguishes a proven swallowing `IgnoreRoute`, a possible Framework
overlap, and a Core tie that nothing readable separates — the last of which is a bug in
the destination unless a host, content type or custom selector policy tells the two apart,
and worth fixing before any more traffic is pointed at it.

**An empty `conflicts` array is only evidence if the proxy was read.** Check `proxyStatus`
on the report before drawing any conclusion from it, and before trusting an ownership
verdict that depends on proxy coverage:

| `proxyStatus` | What it means |
|---------------|---------------|
| `Read` | The proxy was parsed. An empty `conflicts` array means no modeled conflict was found, not that runtime ambiguity is impossible. |
| `NotSupplied` | No proxy project was named, so nothing proxy-related was evaluated. Routes that depend on proxy coverage will be `Unknown (NoProxySupplied)`; `Ignored` verdicts are decided on the Framework side alone and still stand. Re-run with `proxyProjectPath` to get real answers. |
| `Unreadable` | A proxy project was named but would not load. Fix that before reading the report — this is not the same as there being no conflicts. |
| `NotEvaluated` | The scan stopped before the proxy was opened, because the Framework project itself would not load. Read `unresolved` for the reason; supplying a different proxy path will not help. |

**An empty `routes` array does not mean the project has no routes.** It means none were
read. When `proxyStatus` is `NotEvaluated`, the Framework project itself did not load and
nothing was inventoried at all. When `unresolved` carries `MalformedSource`,
`UnsupportedRegistrationApi`, or `UnresolvedSymbol`, registrations exist that are missing
from `routes`. In either case the report is silent about routes that are still serving
traffic, so it cannot support retiring `RouteConfig.cs` or calling a migration finished.

## Environment-specific proxy configuration

Routes read from `appsettings.Development.json` (or any other environment file) are
reported with the file they came from in `source.filePath`. Which file wins is a
deployment fact the repository does not record — **a route that only exists in Development
is not one production serves.** Check the file before planning a wave around it.

## Using the report to plan a wave

1. Run the tool against both projects.
2. If `unresolved` is non-empty, resolve what you can and state the rest as known gaps.
   Do not plan around an inventory you know is partial without saying so.
3. Take the `Forwarded` routes **and every `Partial` route** as the candidate pool.
   Investigate `LocalVersusLocal` entries before excluding anything: a conditional earlier
   registration or one sharing only GET can leave the later route live for other traffic.
   Exclude a candidate only after independently confirming it is unreachable.
4. Group candidates by controller or area, not by route count. Routes that share a
   controller move together or break each other.
5. For each `Partial` route in the pool, identify the remaining slice specifically. This
   is where a wave silently leaves URLs behind.
6. After the wave, re-run and exercise the changed URLs and verbs. When conventional
   action enumeration is available and coverage and forwarder precedence are readable, a
   fully moved route can return `Terminated` at `basis: "Enumerated"`. Core pipeline code can
   instead withhold it as `Unknown` at `OpaqueRegistrar`; load
   [ref/pipeline-code.md](ref/pipeline-code.md), since re-running alone will not clear it. The scaffold's
   `MapForwarder(...).WithOrder(int.MaxValue)` provides a readable last-resort order, not
   proof that every route migrated. Attribute routes need no conventional expansion, so
   not every migrated route has an enumerated basis. Hand-rolled forwarders or unrecognized
   handlers need runtime confirmation: forwarding inside a referenced project can still
   leave a handler classified as local. In all cases, no verdict bypasses "Deleting a Framework
   route": check unresolved gaps, conflicts, and runtime host attribution. For `Partial`,
   inspect candidates and the remaining slice; for `Unknown` at `ProxyPrecedence`, check
   forwarder order and recognizability. Investigate `Unclaimed` as a possible routing gap,
   not proof of a live 404.

## Deleting a Framework route

Two verdicts license deletion, and each has preconditions. Both speak only to inbound
matching: a route that can never match still generates URLs. Generation selects a route by
name — `Url.RouteUrl("live")`, the three-argument `GetVirtualPath` — where deleting it
throws `A route named 'live' could not be found`; or by route values — `Html.ActionLink`,
`Url.Action`, the two-argument `GetVirtualPath` — which walks the collection for the first
route that can build the URL, so deleting it silently returns `null`, a different URL, or
the same URL from another route, naming neither the route nor its object. The report
inventories neither kind. Under either verdict, deletion must change no URL the application
depends on and break no consumer, named or not: searching for the name and for direct
references starts that, and comparing generated URLs is evidence, not proof —
`GetVirtualPath` returns the selected route and its data tokens, not just a string, so a
consumer reading either can break while the URLs compare equal. Preserve or retire every
consumer you find, and where you cannot establish it, do not delete.

`Terminated` licenses it when **all** of the following hold:

- The report was produced with `proxyProjectPath` supplied.
- No unresolved gap can affect that route or its proposed Core replacement. Check both the
  route ID and every ID in `terminatedBy` against `unresolved[].affectedRouteIds`. Entries
  with no affected IDs are unscoped gaps, not harmless ones; resolve them or establish that
  they cannot affect this URL space before deleting anything.
- No Core route named in the route's `terminatedBy` appears in any
  `conflicts[].participantIds`. A `Terminated` verdict already means no forwarder was found
  to preempt that endpoint, so a surviving conflict is one the analysis judged the endpoint
  to win, or one it does not decide. Confirm the endpoint in `terminatedBy` answers.
- Other-project code that a `terminatedBy` handler reaches, or that is handed the application or an endpoint builder, does not answer or forward first; where you cannot establish that, do not delete.
- Inspect references in `redirectTargetIds` and confirm redirects still reach their
  intended destination on Core. A preserved destination URL can outlive its Framework
  registration; a removed destination cannot.

Before deletion, exercise representative URLs and verbs against the deployed Core routing table,
including host restrictions and competing endpoints. The static report models neither every
runtime convention nor every Core-local ambiguity — an empty `conflicts` array proves nothing.

A conflict naming the *Framework* route itself does not block deletion: it describes the
Framework side — a route or `IgnoreRoute` shadowing this one, or a Core fallback answering
whatever reaches it — and changes nothing about whether `terminatedBy` serves the space.

`Ignored` licenses it only when `kind` is **not** `Ignore`. An earlier `IgnoreRoute` on the
same surface swallows such a route before it can match, and the scan models registration
only, so that verdict rests on the ignore still swallowing it when the request arrives.
**Establish that it still does — in every deployment the ignore precedes this route on the
same active surface and matches every request the route would answer. If you cannot
establish it, this verdict licenses nothing.** No list of method names closes that
property; two shapes defeat a name search, each invisible for its own reason:

- The collection changes. `Clear`, `Remove` and `RemoveAt` are receiver calls, excluded by
  syntactic position wherever they appear, so the registering file is not the search
  scope. Assignment through the integer indexer — `routes[0] = replacement`, inherited
  from `Collection<RouteBase>` — is missed differently: it is not an invocation, so no
  receiver filter is reached. `Add` and `Insert` usually reach `unresolved`, but only when
  the receiver is typed as a recognized collection.
- The stored route changes and the collection does not. `Url`, `Constraints`, `Defaults`
  and `RouteHandler` are settable on a `Route`, so
  `((Route)routes[0]).RouteHandler = new MvcRouteHandler()` un-ignores in place: same
  count, same reference, nothing written to the collection for a search to find.

Neither does any search. A mutation sits arbitrarily far from the collection —
`var ignored = (Route)routes[0];` here, `ignored.Url = "x";` in another method, naming
neither `routes` nor `RouteTable.Routes`. Search the whole project for both shapes against
a `RouteCollection` or `HttpRouteCollection`, then follow every alias of the collection and
of the routes it hands out, and confirm none runs after the ignore registers; the order is
set by the composition root calling the registrars, usually `Application_Start`, not the
file this route sits in. Where an alias escapes into code you cannot read, the property is
unestablished and this verdict licenses nothing.

Nothing else licenses deletion. `Partial`, `Unclaimed` and `Unknown` do not, and neither
does a route looking obviously migrated.

**An `IgnoreRoute` itself — `kind: "Ignore"` — is not deletable on this evidence.** It
carries `Ignored` too, so a filter on `ownership` alone returns both it and the routes it
swallows. Its verdict says it is doing its job, not that it is redundant. Removing it
re-exposes the space it was swallowing to every route registered after it.

## Success criteria

- The tool was run with both paths, not one.
- `unresolved` was read and either resolved or reported.
- Every route acted on has a state that licenses that action.
- `Partial` routes were named with their remaining slice, not rounded to done.
- The wave plan distinguishes what is safe to move from what is merely next.
