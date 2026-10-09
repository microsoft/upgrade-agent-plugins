# Where a forwarder delivers

Read this when a Framework route reports `Unknown` at `ProxyPathTransform`, or when `unresolved`
carries an `OpaqueDestination` entry.

## Contents

- [Decision rule](#decision-rule)
- [Why it withholds `Terminated`](#why-it-withholds-terminated)
- [How it appears in the report](#how-it-appears-in-the-report)
- [How to check it](#how-to-check-it)

## Decision rule

Apply this check to **every** Framework route Core covers, including when you predict the report
for a proposed change. Decide by where each forwarder **delivers**, never by its match `template`:
a forwarder whose match space does not overlap the route proves nothing.

- A forwarder with `hasOpaqueDestination: true` may deliver to **any** Framework route, so it
  reaches every route Core covers, whatever its own `template` and whichever route it appears to
  target. A transform the tool does not trust gives it that flag, `AddRequestTransform` included
  even when it only adds a header, and a proxy-wide registration it does not trust gives it to
  every configured forwarder at once (a transform factory, only to those that declare
  `Transforms`). The trusted forms are listed below; the four path keys in `Transforms` and a
  constant `MapForwarder` target path are read into a `destinationTemplate` instead.
- A forwarder with a `destinationTemplate` reaches the route when that destination overlaps the
  route and can carry one of its methods: they share a method, or the route's `httpMethods`
  include `OPTIONS` and the forwarder names a `corsPolicy` and lists `httpMethods`, which makes it
  accept the CORS preflight. A stripped prefix delivered as `/{**path}` overlaps every route.
- If any forwarder reaches it, the route is `Unknown` at `ProxyPathTransform`, or at
  `ProxyPrecedence` or `OpaqueRegistrar` where one of those applies first, and it is **not** safe
  to delete, although `terminatedBy` still names the Core endpoints that cover it.

Counter-example. Core maps `/invoices` and covers the Framework route `invoices`. A new
`MapForwarder` matching `/v1/{**path}` with target path `/{**path}` does not leave `invoices`
`Terminated` because `/v1/...` and `/invoices` look disjoint: `/v1/invoices` arrives at Framework
as `/invoices`, so `invoices` is `Unknown` at `ProxyPathTransform`. A configured forwarder
`reports-proxy` that matches only `/reports/{**rest}` withholds `invoices` the same way once a
proxy-wide `AddTransforms` callback calls `AddRequestTransform`: its destination is unreadable.

## Why it withholds `Terminated`

A YARP forwarder matches one URL and can forward to another. `PathRemovePrefix`, `PathPrefix`,
`PathSet` and `PathPattern` in a route's `Transforms` and a target path handed to `MapForwarder`
change the path Framework receives; code transforms can, including a transformer or request
transform a handler passes to `IHttpForwarder.SendAsync`; and `HttpMethodChange` changes the method.
A forwarder matching `/legacy/{**rest}` that removes `/legacy` delivers a request for
`/legacy/orders` to Framework as `/orders`. A Core endpoint at `/orders` answers only requests made
to `/orders`, so covering the Framework route proves nothing about what that forwarder delivers to
it: the route stays live on Framework while any forwarder can still deliver to it.

The tool reads the four path keys, a constant target path, and transforms in a closed list of YARP's
own forms that leave the path and method alone. In a route's `Transforms` those are the entries
`RequestHeadersCopy`, `RequestHeaderOriginalHost`, `RequestHeaderRemove`, `RequestHeadersAllowed`,
`RequestHeader`, `RequestHeaderRouteValue`, `ResponseHeadersCopy`, `ResponseTrailersCopy`,
`ResponseHeadersAllowed`, `ResponseTrailersAllowed`, `ResponseHeader`, `ResponseTrailer`,
`ResponseHeaderRemove`, `ResponseTrailerRemove`, `X-Forwarded`, `Forwarded`, `ClientCert`,
`QueryValueParameter`, `QueryRouteParameter` and `QueryRemoveParameter`, each with only the companion
keys YARP accepts beside it. In code they are these helpers called with fixed values:
`AddRequestHeader`, `AddRequestHeaderRemove`, `AddRequestHeaderRouteValue`,
`AddRequestHeadersAllowed`, `AddOriginalHost`, `AddResponseHeader`, `AddResponseHeaderRemove`,
`AddResponseHeadersAllowed`, `AddResponseTrailer`, `AddResponseTrailerRemove`,
`AddResponseTrailersAllowed`, `AddXForwarded`, `AddXForwardedFor`, `AddXForwardedHost`,
`AddXForwardedPrefix`, `AddXForwardedProto`, `AddForwarded`, `AddClientCertHeader`, `AddQueryValue`,
`AddQueryRouteValue` and `AddQueryRemoveKey`, and a fixed value assigned to `CopyRequestHeaders`,
`CopyResponseHeaders`, `CopyResponseTrailers` or `UseDefaultForwarders`. `AddRequestTransform`,
`AddResponseTransform` and `AddResponseTrailersTransform` are not on the list, and neither is adding
to `RequestTransforms`, `ResponseTransforms` or `ResponseTrailersTransforms`: each runs code of the
application's own, which can rewrite the path, so any one of them makes the destination unreadable,
as do the path and method helpers such as `AddPathRemovePrefix` and `AddHttpMethodChange`. That
holds for a callback passed to `AddTransforms` for the whole proxy too: one written in
place and built only from those forms does not make a destination unreadable. It trusts these forms
only when it can tell the calls bind to YARP's own methods: a helper it cannot tie to YARP makes the
destination unreadable, and so does a `MapForwarder` or `AddTransforms` call that binds to nothing or
to a namesake declared in source under `Microsoft.AspNetCore`, `Microsoft.Extensions` or `Yarp`,
whatever its arguments hold. An `AddTransforms`, `AddTransformFactory`, `AddConfigFilter` or `MapReverseProxy`
call that binds to a method outside those namespaces is not YARP's, so the tool does not read it as
a proxy-wide registration. Anything else
makes the destination unreadable, and an unreadable forwarder may deliver anything it matches, with
any method, to any route. That includes an `AddTransforms` callback that is not written in place or
holds anything off that list, the other ways of registering transforms for the whole proxy
(`AddTransforms<T>()`, `AddTransformFactory`, `AddConfigFilter`, or a transform provider, transform
factory or configuration filter the application declares or registers) and a `MapReverseProxy(...)`
callback that does more than set up affinity, load balancing or passive health checks
(`UseSessionAffinity`, `UseLoadBalancing`, `UsePassiveHealthChecks`). Many of
those leave the path alone; the tool does not read far enough to say so.

## How it appears in the report

- The Framework route is `Unknown` at `ProxyPathTransform`. `terminatedBy` names the Core endpoints
  proven to cover it, `residualForwarded` is `true`, and `reachedThrough` lists the id of every
  forwarder that may deliver to it. A route withheld for an earlier reason, such as
  `ProxyPrecedence` or `OpaqueRegistrar`, keeps that reason; its forwarders may still need this
  check once that is cleared.
- Each forwarder in `routes` whose rewrite was read carries the path it delivers in
  `destinationTemplate`; one that delivers the URL it matched carries neither field. An unreadable
  one carries `hasOpaqueDestination: true`.
- `unresolved` holds an entry for each unreadable forwarder or registration. Its `affectedRouteIds`
  names the forwarders and the Framework routes withheld through them. The reason is
  `OpaqueDestination`, except `MalformedSource` for a `Transforms` value that does not parse and
  `ConfigDrivenGating` for a forwarder whose id has `Transforms` in a settings file of the other
  kind: any environment file for one read from `appsettings.json`, `appsettings.json` for one read
  from an environment file. Its own file need not declare any.
- A route Core does not cover is judged by where each forwarder delivers, or by what it matches
  where that could not be read, so a rewrite onto the route makes it `Forwarded` or `Partial` as
  usual.

## How to check it

1. Check **every** forwarder that `reachedThrough` lists. One that can still deliver this route's
   requests keeps it unconfirmed, however many of the others you clear.
2. A forwarder with a `destinationTemplate`: find the source URLs in its match space, its own
   `template`, that it delivers to this route. Where the transform has no single inverse, as with
   `PathSet` or a combination that discards the matched path, that is the whole match space. Check
   endpoint selection at those URLs, and for the methods the forwarder and the route share, not at
   one sample: the request still reaches Framework unless a Core endpoint wins there. An empty
   `httpMethods` on either one means every method, so it shares all of the other's. Where the
   route's `httpMethods` include `OPTIONS`, check the forwarder's `CorsPolicy` too: one naming a
   policy accepts the CORS preflight for each of its own methods and passes it on as an `OPTIONS`
   request unless the host's CORS middleware answers it first. `default` and `disable` always
   load, in any letter case; a route naming any other policy the host does not register makes
   YARP refuse the whole proxy configuration, so the host does not start. Under
   `UseCors` the middleware
   answers it for `disable` and for a policy it finds, but not for `default` with no default
   policy registered; without `UseCors`, every request the forwarder is selected for throws,
   because no middleware handled its CORS metadata, unless the host sets
   `SuppressCheckForUnhandledSecurityMetadata`. The tool does not read that setup, so send the
   running proxy a preflight: an `OPTIONS` with `Origin` and `Access-Control-Request-Method`
   headers, since a plain `OPTIONS` is not one.
3. A forwarder with `hasOpaqueDestination`: find its entry in `unresolved` by its id or this
   route's in `affectedRouteIds`, and read the transform or registration it names. Then observe, on
   the running proxy, the path and method it sends to Framework for requests in its match space.
4. An entry for the proxy pipeline callback passed to `MapReverseProxy(...)`: review its code as
   [pipeline-code.md](pipeline-code.md#how-to-review-it) describes, **and** follow the steps above
   for each forwarder it reaches. A runtime observation does not replace the code review: the
   callback runs on every proxied request, and one request shows one path through it.
5. `Transforms` merged across settings files (`ConfigDrivenGating`): a run loads `appsettings.json`
   and one environment file, and configuration merges their `Transforms` arrays entry by entry, so
   the forwarder's own file does not show what runs. Two environment files never merge. The row
   names the forwarder's file and the others. Read `appsettings.json` and the file for the
   environment you deploy to, and merge the two entries at each index key by key: the merged entry
   holds the keys of both, and where both set the same key the environment file's value wins. Check
   the merged list as above.
6. The settings files are only what can be read statically. Environment variables, command-line
   arguments and any other configuration source the host adds bind over them, and
   `ReverseProxy__Routes__legacy__Transforms__0__PathRemovePrefix` is an ordinary deployment
   override. Ask whether the deployment sets a forwarder's route or `Transforms` that way: merge one
   you can read as in step 5, and treat the destination as unreadable where you cannot.

Report the route as unconfirmed, not as moved: name each forwarder and say what your check found it
delivers to this route. That reading is evidence to give the user, not a deletion licence, and
whether to delete the route is the user's decision. Do not change or remove a transform to earn
`Terminated` back: the clients of the forwarder depend on the path it delivers.
