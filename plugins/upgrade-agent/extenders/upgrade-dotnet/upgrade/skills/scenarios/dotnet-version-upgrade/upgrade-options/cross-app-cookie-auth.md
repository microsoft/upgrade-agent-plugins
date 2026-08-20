<!-- Provenance: the two mechanisms, their tradeoffs, and the staged sequencing below are
     distilled from specs/repos/nuget-gallery/nugetgallery-crossapp-auth-spec.md (sections 5,
     7.3, 7.4, 8, 9). That spec is a maintainer reference and does not ship with the plugin,
     so it is cited here rather than linked. -->

# Cross-App Cookie Authentication

**Category**: Compatibility
**Plan impact**: No

**Applicable when**:
- A .NET Framework web project authenticates browser requests with a cookie. Any of:
  - Forms authentication (`<authentication mode="Forms">`, `FormsAuthentication.*`)
  - OWIN/Katana cookie middleware (`UseCookieAuthentication`, `CookieAuthenticationOptions`)
  - ASP.NET Identity sign-in
  - A hand-rolled authentication cookie protected by `<machineKey>`
- AND the web project's **Project Approach** value is **Side-by-side** — the Framework
  and Core hosts must run at the same time for there to be anything to share

Project Approach is resolved in this same Step 1.5 pass, so read its **selected or
recommended** value, not a confirmed one. If the cross-option coherence check later moves
Project Approach to **In-place rewrite**, this option stops being applicable and drops out
of the payload entirely.

Where Project Approach produced no value at all for the project, fall back to whether the
migration will actually run both hosts concurrently. `project-approach.md` sections cover
MVC/WebAPI web projects and class libraries, so a Web Forms project — the live case, since a
Web Forms to Blazor Server migration is planned side-by-side and is exactly the shape that
needs a shared cookie — may never receive a value. Treat a missing Project Approach as
non-blocking in that situation rather than as a reason to drop this option; a project type the
approach option does not classify has not chosen In-place rewrite.

**Not applicable when**:
- The web project's Project Approach is **In-place rewrite** — one host serves traffic, so
  no cookie crosses a boundary
- No .NET Framework web project authenticates browser requests with a cookie (anonymous
  site, Windows authentication, or token/API-key authentication only). A `<machineKey>`
  entry alone does not qualify — it commonly protects only ViewState or anti-forgery
  tokens — and neither does OWIN security middleware that issues bearer tokens rather than
  a cookie
- All web projects already target modern .NET
- The team accepts a **session reset** — every signed-in user signs in again at cutover.
  No interop mechanism is needed and neither choice below applies
- Neither mechanism is available for the solution — see **Default logic** step 3. The
  migration can still proceed, but with a session reset at the host boundary, which is
  carried as a task risk rather than as an option

**Default logic**: establish which values are actually available first, then recommend among
them. Never recommend a value the solution cannot restore.

1. **Establish availability.** **Shared Cookie (Data Protection interop)** is available only
   when every condition under **Shared Cookie availability** holds. **Remote Authentication**
   needs the Framework host on .NET Framework 4.7.2 or later, which is what the adapters
   Framework package supports — but treat that as a prerequisite rather than a verdict. A host
   below 4.7.2 that can be retargeted still has Remote Authentication available; only a host
   pinned below 4.7.2 by a dependency that cannot move does not. When the evidence does not
   settle whether a pin is movable, treat the host as retargetable and carry the retarget
   forward as an unverified prerequisite when presenting the choice — ruling the value out on
   an unconfirmed pin removes a mechanism the solution may well support, which is the worse
   error. Shared Cookie needs only 4.6.2, so a host pinned in the 4.6.2–4.7.1 band can have
   Shared Cookie available and Remote Authentication not.
2. **Intersect across web projects.** One value is recorded for the whole solution, so a
   value is available only if it is available for *every* applicable cookie-authenticated web
   project. A solution pairing a net48 Forms host with a Katana host pinned at net462 has
   neither value available: Forms rules out Shared Cookie for the first, and the pin rules out
   Remote Authentication for the second.
3. **If neither value survives, the option is not applicable — omit it from the confirmation
   payload rather than recording a value.** `selected` has to match one of the declared
   choices, so "neither" cannot be represented in the payload; do not invent a value and do
   not record one the host cannot run. Follow the index rule for non-applicable options
   exactly: do not name this option or either of its values anywhere, and do not write
   evaluation reasoning during Step 1.5.
   The *consequence* survives without naming anything here: identity crossing the host boundary
   is unresolved. `planning.md` carries that in the web-migration task's **Known risks**, in the
   task's own words, including the rule against stating the sign-out as settled. The absence of
   a confirmed value stays ambiguous all the way through — `migrating-mvc-system-web-adapters`
   Step 3 deliberately maps every absence to its pre-option default rather than guessing which
   absence it is looking at.
4. **If exactly one value survives, recommend it** and say why the other is unavailable. Two
   cases matter. When the survivor is **Shared Cookie (Data Protection interop)** it overrides
   the standing default in step 5 — present it as forced by availability, not as a preference.
   When the user asked for shared cookies but a prerequisite failed and **Remote
   Authentication** is the survivor, recommend it and name the prerequisite that blocked
   Shared Cookie, so the user can decide whether to change it rather than being silently
   overruled.
5. **If both survive, recommend Remote Authentication**, unless the user has explicitly asked
   for shared cookies. It is the standing default: the Framework host stays the single
   identity authority, no cookie crypto has to be aligned, and the change is the smallest
   reviewable one. Recommend **Shared Cookie (Data Protection interop)** only on an explicit
   request.

Environmental evidence that the prerequisite work is small — for example key material
already pinned off-machine in a shared store — is worth **mentioning when presenting the
choice**, because it tells the user the second option is cheaper than it looks. It is not
grounds for switching the recommendation on its own. Shared Cookie has the higher blast
radius (a key-ring, application-name, purpose, or ticket-format mismatch signs everyone
out at once), so it is selected deliberately, never inferred.

**Options**:
- **Remote Authentication** *(default when both values are available)* — costs a per-request
  hop to the
  Framework host, which must stay reachable from Core for as long as this is in place, but
  needs no cookie-format or key work at all. The Core host asks the Framework host to
  authenticate, forwarding the inbound cookie and a shared API key, and materializes the
  returned principal. Format- and key-agnostic: no Data Protection alignment, no
  ticket-format work. Requires the Framework host to target .NET Framework 4.7.2 or later,
  which is what the adapters Framework package supports. It is also the first stage of the
  recommended path — see **Phasing**.
- **Shared Cookie (Data Protection interop)** — removes the per-request hop, but both hosts
  must agree exactly on a shared Data Protection key ring, application name, scheme, purpose
  triple, ticket format, cookie name, and chunk layout, and it takes a staged rollout the
  team must drive. It is the better steady state under load, but there are more moving parts
  to get exactly right and a misconfiguration is a mass sign-out. The rollout cannot be
  completed in one pass: a dual-format reader ships first, then at least one full cookie
  lifetime has to elapse under monitoring before authenticated Core routes open, and the
  legacy reader is retired later still. Those steps need deployments and production
  telemetry, so they land on the team rather than the agent.

**Shared Cookie availability**: **Shared Cookie (Data Protection interop)** is a
Katana/OWIN mechanism. It is available only when all of the following hold — with the
single documented exception for an unverified ticket store noted below. When one fails, say
which condition ruled it out and fall through to **Default logic** step 3 or 4, rather than
assuming **Remote Authentication** can be offered instead; it has its own floor:

- The Framework host runs OWIN/Katana cookie middleware under `Microsoft.Owin.Host.SystemWeb`.
  The bound skill rejects a missing host data-protection provider rather than falling back
  to machine-local key material, and adding the package does not convert an OWIN self-host.
- The Framework host targets .NET Framework 4.6.2 or later. The interop package ships only
  a `net462` assembly, so an earlier target cannot restore it. Below 4.6.2 the bound skill
  stops and asks for a retarget, which is usually unwelcome on a host that is meant to stay
  put during a side-by-side migration — so do not offer the choice unless the user has
  accepted retargeting first.
- No `CookieAuthenticationOptions.SessionStore` / `ITicketStore` is configured. A
  server-side ticket store hands the other host an opaque session key it cannot resolve, so
  the cookie is unshareable no matter how the keys are aligned.

The ticket-store condition is the one that may not be answerable from what has already been
read. The ban on opening files applies to *trigger* evaluation; once this option has loaded,
reading the OWIN `Startup` cookie-middleware registration to settle it is in scope. If it
has still not been established, treat it as the one exception to the rule above: do not
assume absence — offer Shared Cookie with the unverified prerequisite named, so the user can
confirm it rather than discovering it when the bound skill stops.

One value is recorded for the whole solution, so every applicable cookie-authenticated web
project has to satisfy the conditions above before Shared Cookie is available — see
**Default logic** step 2. A mechanism that works for some hosts and not others is not an
available value.

Keeping the existing cookie name is a constraint on *executing* Shared Cookie, not a test
for offering it: the name can always be preserved by configuring it explicitly, and the
bound skill stops and asks for confirmation rather than renaming silently. Do not treat it
as an availability condition.

Forms authentication and hand-rolled `<machineKey>` cookies make this option **applicable**
— those apps have a cross-host cookie problem and need an answer — but they have no Katana
cookie middleware to retarget, so Shared Cookie is never available to them. Their answer is
**Remote Authentication** when its own 4.7.2 floor is met, and otherwise the no-value
outcome in **Default logic** step 3. Do not offer Shared Cookie to them.

**Interactions**:
- **System.Web Adapters + Shared Cookie**: when System.Web Adapters is **Use System.Web
  Adapters** and this option is **Shared Cookie (Data Protection interop)**, the adapters
  remote-app wiring must omit its authentication client. Both mechanisms would otherwise
  authenticate every request — once from the shared cookie and once over the hop — which
  is wasted work at best and a redirect loop behind the reverse proxy at worst. The
  shared-session client is a separate concern and stays. The rule is also written into
  `migrating-mvc-system-web-adapters` itself, which is what enforces it at execution time.
  **This pairing is valid and must not be adjusted.** It is a wiring instruction, not a
  contradiction between two selected values: do not "resolve" it by moving this option to
  **Remote Authentication** or System.Web Adapters to **Direct Migration to ASP.NET Core
  APIs**. Shared Cookie is only ever selected on an explicit request, so flipping it away
  discards a decision the user made deliberately.
- **Project Approach**: applicability depends on the web project's Project Approach value
  being **Side-by-side**. If the coherence check moves it to **In-place rewrite**, remove
  this option from the payload rather than leaving a selection the user cannot act on.
- **How each choice is delivered**: Remote Authentication does not technically require the
  System.Web Adapters shim overlay — the remote-app packages are separable from the
  compatibility shims. But in this product its guidance ships only inside
  `migrating-mvc-system-web-adapters`, which loads only when the System.Web Adapters option
  is **Use System.Web Adapters**. So when this option is **Remote Authentication** and
  System.Web Adapters is **Direct Migration to ASP.NET Core APIs** — or was never applicable
  at all, as on an OWIN self-host with no `System.Web` — say plainly that the remote-auth
  wiring will not be walked through step by step. This is a delivery constraint, not a
  platform one. **This pairing is valid and must not be adjusted.** Do not flip System.Web
  Adapters to **Use System.Web Adapters** in order to obtain the walkthrough: that forces the
  entire shim overlay onto a user who declined it, which is a far larger change than the
  guidance is worth. A reduced walkthrough is the expected outcome here, not a contradiction
  to resolve.
- **Side-by-side scaffolding**: when the ASP.NET Core host is created by
  `scaffolding-yarp-proxy-project`, that scaffold can pre-wire either mechanism on the Core
  side, and it reads this option's confirmed value to decide which. The value is therefore
  consumed at scaffold time as well as during the migration steps. It is settled here, so the
  scaffold does not re-derive it — but note that mechanism-specific prerequisites it enforces
  (such as a minimum System.Web Adapters package version for the remote path) can surface
  after this option is confirmed. Those are raised with the user rather than resolved by
  silently switching mechanism.

**Phasing** *(only when both values are offerable — see **Shared Cookie availability**)*: the
two values are stages of one path, not a permanent fork. Starting on
**Remote Authentication** proves the cross-host plumbing with the smallest reviewable
change, then switching to **Shared Cookie (Data Protection interop)** before the Core host
carries meaningful authenticated traffic removes the per-request hop. The switch is
localized to the authentication wiring and does not require revisiting controllers that
already moved. A user who picks Remote Authentication is not shut out of shared cookies
later, and one who picks Shared Cookie first is skipping a proving step, not taking a
shortcut. Say so when presenting the choice.

Do not offer that narrative when Shared Cookie is not an available choice for this solution.
A Forms-authentication or `<machineKey>` app has no Katana cookie middleware to retarget, so
telling its owner they can move to shared cookies later is a promise the mechanism cannot
keep — reaching it would mean adopting Katana cookie middleware first, which is a larger
change than either value here describes.

**Identity endpoints under both choices**: login, logout, registration, MFA,
external-provider challenges and callbacks, and the temporary external-login cookie stay on
the Framework host and migrate later as one unit. Each form-rendering GET also stays on the
same host as the POST it submits to, because Framework and Core anti-forgery token formats
are not interoperable even when a key ring is shared. Both constraints apply to **Shared
Cookie** exactly as they do to **Remote Authentication** — do not present them as a cost of
one mechanism. What is distinctive to **Remote Authentication** is the per-request hop and
the Framework host having to stay reachable from Core; what is distinctive to **Shared
Cookie** is the up-front key, purpose, and ticket-format alignment and its rollout
discipline.

**Stored as**: `Upgrade Options > Compatibility > Cross-App Cookie Authentication`

**Skill**: `sharing-authentication-cookies-katana-interop` (Shared Cookie (Data Protection interop))

That skill is loaded for the migrate phase when its value is confirmed. **Remote
Authentication** deliberately carries no skill binding of its own: its guidance lives in
`migrating-mvc-system-web-adapters`, which the System.Web Adapters option already loads
whenever that option is **Use System.Web Adapters**. Binding it here as well would load the
whole shim overlay even when the user chose **Direct Migration to ASP.NET Core APIs** —
the opposite of what they asked for. Do not add that binding back.

**Affects**: authentication wiring in the scaffold and migrate tasks for side-by-side web
projects, which identity-related routes may move and when, and whether the adapters
remote-app wiring registers an authentication client.
