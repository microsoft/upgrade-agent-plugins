# Pipeline code ahead of Core endpoints

Read this when a Framework route reports `Unknown` at `OpaqueRegistrar` while `terminatedBy`
names Core endpoints, or when `unresolved` carries an `OpaqueRegistrar` entry for Core code.

## Contents

- [Why it withholds `Terminated`](#why-it-withholds-terminated)
- [How it appears in the report](#how-it-appears-in-the-report)
- [How to review it](#how-to-review-it)

## Why it withholds `Terminated`

Coverage is proven among endpoints only, and middleware runs before any endpoint is
selected. Under `WebApplication` the endpoints run last unless the code calls
`UseEndpoints` itself, so pipeline code may answer, re-path or forward the request to
Framework before the endpoint in `terminatedBy` sees it. Position is not read: code written
after an explicit `UseEndpoints` runs only when no endpoint answered, and it withholds
`Terminated` all the same. So does code on the builder that
`app.UseExceptionHandler(errorApp => ...)` or `app.UseStatusCodePages(errorApp => ...)` hands
its lambda (`errorApp.Run(...)`), although that pipeline runs only after the request has
failed; its entry names the pipeline and says so. The tool counts as pipeline code:

- a middleware branch: `app.Map(...)`, `MapWhen`, or a `UseWhen` whose own configuration
  claims, or whose predicate may change the request: anything but a lambda that only reads
  it, since the predicate runs for every request;
- inline, custom or third-party middleware: `Use`, `Run`, `UseMiddleware<T>`, a `Use*`
  extension outside ASP.NET Core's own routing-neutral set, or a method in a referenced
  project that is handed the application builder, whether it is called directly or passed on
  as a delegate (`Action<IApplicationBuilder> configure = LegacyPipeline.Register;`), and so
  is a delegate property a referenced project declares, and `Build()` on a pipeline builder,
  called or passed on as a delegate. A `Map` or `UseWhen` that ASP.NET Core did not compile, such
  as a same-named extension in a referenced project or one that does not bind, is such a method,
  not a branch; one the project declares is read through its code, like any method it declares;
- a method or delegate property the project declares that takes the application builder and is
  reached through an interface or abstract member, where the call does not show which body
  runs: a default interface method, instance or `static virtual`, that a class satisfies
  with a member it inherits from a referenced project; an interface or abstract method that
  nothing in the project implements, or that a class implements through a referenced
  project's base; or an interface member called on a parameter or a value whose exact type
  the code does not show. The tool reads the project's own code for a method where the call
  fixes the body that runs: a non-virtual or static method, or a sealed override; a `base.`
  call; a receiver created in place, a local only ever set to one, or a value of a sealed type
  or a struct, whose own implementation is in the project. It also reads a class's virtual
  method, or an override, whatever the receiver, since that method and every override of it
  are the project's own code; and an abstract method, an interface method without a default
  body included, when every class or struct in the project that implements it does so with
  the project's own code. A delegate property or indexer is read when it is non-virtual, a
  class's virtual property, or reached through `base.`; an interface or abstract one is
  pipeline code whatever the receiver, and so is one a referenced project declares. An
  element of a collection of delegates (a `List<Action<IApplicationBuilder>>` read by index,
  an array, a `foreach`) is not checked, so pipeline code a referenced project puts in one
  is not seen. A callback handed to a member is read as run where the call fixes the body
  that runs, as listed above, or, for a class's virtual or abstract method, where every body
  the project declares for it (its own unless abstract, and every override) runs it; so an
  endpoint mapped in a callback handed to an interface member reached through a value of
  unknown type is conditional, and so is one handed to a class method an override in the
  project drops, or to an abstract one nothing in the project overrides. A call that an
  interceptor replaces is never read through the code it names: a method the project declares,
  or ASP.NET Core's own middleware (`UseRouting`, `Map`, `UseWhen` and the rest) included, is
  pipeline code if it is handed the application builder; and a callback handed to any call an
  interceptor replaces is not read as run. Nor is a callback handed to a referenced project's
  virtual or interface member that a type in the project overrides or implements, unless the
  call shows which body runs: the referenced project's own code for that member, or the
  project's own code   where that code runs the callback. An implementation of a referenced project's interface that
  a class in the project inherits from a referenced project counts as such a type, and so does
  a class in the project that inherits a referenced project's override of the member; the
  inherited code is not read as running the callback either;
- a rewriter or `UsePathBase`;
- an `IHttpForwarder.SendAsync` that no endpoint owns, or one in a handler method that other
  code also calls, or one inside a branch or `MapReverseProxy` callback that the branch itself
  does not run (a delegate held in a variable there, a local function).

A per-request callback that ASP.NET Core's own middleware takes, such as
`CookiePolicyOptions.CheckConsentNeeded` or a `CustomRequestCultureProvider`, is not read for
what it changes, so one that re-paths the request does not withhold `Terminated`.

When the route itself is `Unknown` at `OpaqueRegistrar` and an entry naming pipeline code
reaches it, that code is enough to withhold `Terminated`, but the verdict does not say it is
the only cause. The same reason covers a Core endpoint registered through code the tool
cannot read, so `terminatedBy` names either endpoints proven to cover the route or only
candidates, and the report does not always say which. Either way the verdict licenses
nothing. An entry can also reach
routes that are `Forwarded` or `Partial`; pipeline code does not change those verdicts, and
their `terminatedBy` is empty or names only part of the space. A local-looking answer from the
running host does not settle it either, because a forwarded response can be indistinguishable
from a local one.

A proxy built by the YARP scaffold usually has such code: the templates always emit
`app.UseSystemWebAdapters()`, and on .NET 10 and later the scaffold also emits a
response-header scrubber (`app.Use(...)`). Where either is present, every route that would
otherwise be `Terminated` reports this, including the routes a finished wave moved. Say so
rather than treating it as a defect in the wave.

## How it appears in the report

- Most pipeline code appears twice: as a `kind: "Middleware"` record in `routes` over the
  whole space (`{**path}`), and as an `unresolved` entry naming the call and its line. That
  entry has no affected IDs, because what the code claims is decided by code the tool does
  not evaluate. It is an unscoped gap.
- `app.Map(...)` with a readable prefix is the scoped case. Its entry names the branch
  record and every route on either host that its prefix can reach. An endpoint registered
  inside a branch configured by a lambda or by a method the project declares carries a
  predicate atom naming the branch, which makes it conditional, and so does one mapped by a
  method passed to a call there that runs it (`branch.UseEndpoints(MapLegacy)`). A branch
  configured by a delegate held in a variable, or a method passed on as a delegate anywhere
  else, gets an opaque atom instead ("stored rather than invoked", or "handed on as a
  delegate"): conditional too, but it does not name the branch. An endpoint mapped in the
  configuration of any other ASP.NET Core call that builds a pipeline of its own, such as
  `app.UseExceptionHandler(errorApp => ...)`, which serves only failed requests, carries an
  atom naming that call as its branch; the host's `Configure` is the exception. Code written in a branch callback, or in
  YARP's own
  `MapReverseProxy` callback, stays the branch's only in a short list of shapes: an ASP.NET
  Core or YARP call on the callback's own builder parameter, named directly and never
  reassigned, or on a fluent chain from it, that returns nothing or a builder and is handed no
  middleware declared elsewhere (`branch.UseRouting().Use(...)`, `branch.Run(...)`,
  `proxy.Use(...)`), and the lambdas such a call is handed (`branch.UseWhen(..., b => ...)`).
  A middleware lambda there stays the branch's only while it just invokes or returns its
  `next`. Anything else there is whole-space, as though it were written at the top level:
  code on the application (`app.Use(...)`, `app?.UseMiddleware<T>(branch)`), on the branch
  held in a local or cast, reassigned, or called through `?.`, the branch handed to a method
  outside ASP.NET Core and YARP, as an argument or as the callback itself
  (`app.Map("/admin", LegacyAdmin.Configure)`), a lambda held in a variable or a local
  function, a middleware
  declared outside the callback (`branch.Use(Pass)`), a delegate returned by code in a
  referenced project, `branch.Build()`, whose request delegate can be registered anywhere, and
  a middleware's `next` (or `StatusCodeContext.Next`) handed on rather than invoked, which is
  that same delegate. Some of these are the branch's own code; the tool withholds rather than
  guess.
- A handler that calls YARP's `IHttpForwarder.SendAsync`, directly or through a type that
  implements it, is not this gap. It is reported as
  `kind: "Forwarder"` with the destination in `forwardTarget` (no destination when no single
  one can be read), and the routes it serves are
  `Forwarded`. That holds even when the forward runs only under a condition and the handler
  answers other requests itself, or when the `SendAsync` it calls is an overload the application
  adds to the forwarder and answers the request, so read the handler before telling the user what it serves;
  either way the Framework route stays. If other code also calls that handler method, such as another handler or a
  controller action, the forward also appears as whole-space pipeline code, because it serves
  routes that are not its own. Only code in the project is read: a handler that is itself in a
  referenced project, or that calls code there which forwards (another library's
  `IHttpForwarder` wrapping YARP's included), reads as a local endpoint. So
  does a local endpoint outranked by a forwarder that code in a referenced project maps when it
  is handed an endpoint builder: the application (`LegacyEndpoints.MapLegacy(app)`), or the
  builder of a `UseEndpoints` anywhere, a branch or `MapReverseProxy` callback included
  (`b.UseEndpoints(e => LegacyEndpoints.MapLegacy(e))`). A branch does not confine its
  endpoints to its prefix: once the application has called `UseRouting()`, endpoints mapped
  through a branch's `UseEndpoints` are the application's own. A lambda handed a builder by a
  call into a referenced project is read as run there and then, so an endpoint in one that the
  project keeps and never runs (`Deferred.Store(b => b.UseEndpoints(...))`) reads as a local
  endpoint too.

## How to review it

Read the `unresolved` entries without affected IDs, and those naming the route. Confirm each
one by reading the code it names: what it answers, what it re-paths, and what it forwards.
Do not settle it by probing the running host. Middleware that always calls `next` and leaves
the path alone takes nothing, but the tool does not read that far, so the route stays
`Unknown`. Your reading is evidence to give the user, not a deletion licence.

Report the route as unconfirmed, not as moved: name each entry, and say what your reading
found it does with this route's requests. Whether to delete the route is the user's decision.
Do not remove, move or disable pipeline code to earn `Terminated` back, the scaffold's
`UseSystemWebAdapters()` and scrubber included: the application depends on it, and changing
it changes what the application serves.
