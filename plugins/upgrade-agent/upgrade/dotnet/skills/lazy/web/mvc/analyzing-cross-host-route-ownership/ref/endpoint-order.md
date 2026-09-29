# Interpreting endpoint order

Read this for `ProxyPrecedence` before interpreting conflicts or changing a registration's
order. `terminatedBy` names the covering endpoints and `conflicts[]` names the forwarder —
that is a lookup, not a pointer: no field on the route record names it, and it can return
**more than one** conflict. The route is withheld when any one slice of its URL space is
lost, while each overlapping pair is reported separately, so a route spanning several
verbs or URLs carries one conflict for each covering endpoint that overlaps a forwarder,
and those conflicts can disagree.

Read the **last sentence** of each `evidence` before the numbers in front of it. That
sentence is this analysis's finding on that pair; the order clause ahead of it is only
the working:

- **`The proxy may win, or an equal-priority tie may be ambiguous…`** — the pair is in
  doubt. On a route carrying several conflicts these are the ones that explain the
  verdict, and the ones to act on.
- **`The local endpoint wins endpoint selection…`** — the pair is settled, and it does
  **not** clear the route: another conflict on the same route is why the verdict was
  withheld. A `LocalVersusCatchAll` never carries this sentence, because a local that
  provably beats a catch-all is not reported at all; a `ProxyVersusLocal` carries either,
  because it reports the overlap whether or not the local wins.

The order clause ahead of that sentence says how the winner was, or was not, established.
It is one of three:

- **Both orders were read** — the evidence prints them, as in `Local Order is 2; proxy
  Order is 0.` The lower number wins outright, whichever side it is on; equal numbers go
  to a second stage:
  - **The proxy's number is lower.** It wins. Treat the Framework route as **still live**.
  - **The local's number is lower.** It wins, and the last sentence says so.
  - **The numbers are equal.** Core breaks the tie on template precedence, so the last
    sentence is decided there rather than by the numbers. One shape clears: a local
    endpoint that is not a `MapControllerRoute` and whose template is more specific than
    the forwarder's. Three do not — a `MapControllerRoute` carrying an explicit `Order`,
    where the tiebreak is declined outright because the template on file is the
    registration and Core matches requests against the action endpoints it expands into,
    whose precedence is not the registration's; templates of equal precedence, where
    there is no winner on shape and — if nothing in the endpoints' selection metadata
    separates them either — Core raises `AmbiguousMatchException` and **neither** host
    serves the URL; and a forwarder of higher precedence, which wins, leaving Framework
    still serving that URL. Where the last sentence expresses doubt, open both
    registrations: equal numbers then tell you the tie was not broken in the local's
    favour, not who serves the request.
- **`Their relative Order is not established.`** — either the Core side has no `Order` to
  read, or something on one side could not be read at all.
  - Without a declared order, conventional routes are numbered from a counter starting
    at 1, while an unordered forwarder sits at 0. In that arrangement the forwarder
    wins; treat the route as **still live**.
  - An unreadable constraint, endpoint convention or malformed template defeats the
    comparison whatever the orders say. On a recognized endpoint builder, including
    `MapForwarder`, an `Add` or `Finally` convention containing only a single assignment
    of a constant to `RouteEndpointBuilder.Order` can be read when the builder and
    assignment are recognized. A computed value, additional work, or an untraceable
    builder keeps the comparison unproven.
  - On `MapReverseProxy()`, any endpoint-order convention, including `WithOrder`, makes
    every configured forwarder opaque; this also applies to conventions on its enclosing
    group. Do not infer effective order from configuration alone: those conventions can
    override it. Inspect the unresolved entries and confirm endpoint selection at runtime.
- **`The proxy declares the last-resort Order int.MaxValue; a conventional registration
  is numbered from a counter that cannot reach it, so the local endpoint takes the
  request.`** — a **local win** proven without a comparison: there is no pair of numbers
  to print, because the winner follows from the ceiling on the registration counter
  rather than from an `Order` Core stated.
  The overlap is still reported, because both templates claim the space — that is not a
  doubt about who serves the request.
  - This does **not** exempt the route from the skill's deletion gate. A conflict naming a
    `terminatedBy` route still blocks deletion; the way through is the confirmation
    against a running host, not an exemption. The clause tells you what you are confirming.

To establish the order, declare an explicit `Order` on the **Core registration** —
raising the forwarder's instead can change which endpoint wins without making the
comparison readable — then confirm against a running host before treating the route as migrated.
