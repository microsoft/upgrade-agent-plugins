---
name: migrating-federated-oidc-token-exchange
description: >
  Migrates an endpoint that exchanges an external identity provider's workload token for a
  short-lived application credential — trusted publishing, workload identity federation,
  federated credentials, OIDC credential exchange. Use when the application accepts a JWT
  minted for a CI job or service principal by an external issuer, matches its claims against
  a stored trust policy the application owns, and mints its own API key or token in response.
  Triggers for "trusted publishing", "trusted publisher", "workload identity federation",
  "federated credential", "OIDC token exchange", "exchange an OIDC token for an API key",
  "trust policy", "short-lived API key", and "CI token exchange endpoint". This is a
  behavior-preserving migration: the exchange logic is application security code that must be
  moved intact, not redesigned. Not for securing an API with a fixed-authority bearer scheme
  where the inbound token is itself the credential — that is a scheme configuration and has
  its own migration path.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Migrate a Federated OIDC Token-Exchange Endpoint

## Overview

Some applications accept an external identity provider's *workload* token — the JWT a CI
system or cloud platform mints for a build job or a service principal — and trade it for a
short-lived credential the application itself issues. The caller never holds a long-lived
secret; the CI platform vouches for the job, the application decides whether that job is one
of its trusted publishers, and issues a credential scoped to the work.

This is not authentication middleware. It is an **exchange**: a request-scoped transaction
with a trust-policy store, claim matching, replay prevention, and credential issuance in the
middle of it. Recognizing that is the whole job, because the two ways to get this wrong pull
in opposite directions.

**Failure mode A — gratuitous rewrite.** Exchange code frequently sits inside a
Framework-only compile island: a multi-targeted project that excludes the authentication
folder for the portable target, or a project that has not been converted yet. An agent that
sees a `net472`-only island full of legacy references concludes the contents are legacy and
rewrites them. Usually they are not. The token-validation core of this shape —
`Microsoft.IdentityModel.*` and its companions — is portable already and often referenced
unconditionally. The exclusion is a **folder-wide glob** that swept the exchange in
alongside genuinely coupled neighbors.

**Failure mode B — freezing coupled code.** The opposite reflex is just as wrong. Guidance
that says "do not touch this" leaves real framework coupling in place and offers nothing
when un-excluding the folder does not compile.

So the first instruction of this skill is neither *rewrite* nor *preserve*. **It is to
classify**, file by file, and then apply the branch that file earned.

### Why the controls fail silently

Both failure modes converge on the same casualty. Replacing an exchange with a bearer
scheme and a token-issuing call compiles, runs, and authenticates — while dropping the
required-claim gate, the deny-list of trigger values, the ordering that keeps claim matching
behind successful validation, the staged error disclosure that keeps the endpoint from
becoming an enumeration oracle, replay prevention, first-use identifier binding, and the
bounded credential lifetime.

**Nothing fails. Everything still authenticates. The trust boundary is gone.**

That is why this migration is behavior-preserving, and why the checklist at the end is the
artifact that matters more than any code in this skill.

Every snippet here is C#. A Visual Basic application must translate them; the shape is
language-independent.

> **Related skills:** For a fixed-authority bearer scheme where the inbound token *is* the
> credential, see `migrating-owin-oauth-to-jwt`. For a scheme the application implemented
> itself by deriving from the Katana `AuthenticationHandler<TOptions>`, see
> `migrating-owin-authentication-handler-to-core` — but route the exchange here even when it
> happens to be written as a handler, because splitting validation from issuance severs one
> trust decision. For interactive sign-in, see `migrating-owin-openid-connect`. For the
> surrounding MVC or Web API host, see `migrating-mvc-authentication` and
> `migrating-mvc-controllers`.

### Not this shape

| What you are looking at | Where it goes |
|---|---|
| Inbound token is the credential; one fixed authority configured at startup | `migrating-owin-oauth-to-jwt` |
| Application implements its own scheme by subclassing the Katana handler, and only validates | `migrating-owin-authentication-handler-to-core` |
| Browser sign-in, authorization code, redirects, sign-out | `migrating-owin-openid-connect` |
| Cookie issuance and validation | `migrating-owin-cookie-auth` |
| **Inbound token is evidence; application matches it to a stored policy and mints a different credential** | **this skill** |

## Reference material

- [Provider protocol facts](ref/providers.md) — issuer authorities, audiences, identifier
  claims, and matchable claims for the common workload issuers.
- [A worked example](ref/worked-example.md) — one production implementation end to end,
  including its starting state and the seams it has to cross.

## Workflow

```text
Migration progress:
- [ ] Step 1: Confirm the shape
- [ ] Step 2: Classify every file
- [ ] Step 3: Branch A — move portable files unchanged
- [ ] Step 4: Branch B — port the coupled seams
- [ ] Step 5: Place lifetimes and dependencies
- [ ] Step 6: Verify against the behavior-preservation checklist
```

### Step 1: Confirm the Shape

Points 1, 3 and 4 are required. If any of those is missing, this is not an exchange, and the
table above routes it.

1. An inbound JWT the application did not mint, presented to a specific endpoint rather than
   to a scheme protecting many endpoints.
2. Often, **more than one possible issuer**, chosen per request from the token itself rather
   than configured once at startup. This is common but **not definitional** — a
   single-issuer exchange is still an exchange, and it still needs every control below.
3. A persisted **trust policy** owned by the application, matched against the token's claims.
4. An **outbound credential** the application mints, distinct from the inbound token and
   with **its own bounded lifetime**.

Point 4 is the one that decides. If the request completes with the caller authenticated and
nothing new issued, it is a scheme. If the response body carries a new secret, it is an
exchange.

### Step 2: Classify Every File

Do this before moving anything. Produce a written list; the branch decision is per file.

A per-target `Compile Remove` glob, or a project that has not been converted, is a
**recognition signal, not a verdict**. Globs exclude folders, and folders hold unrelated
neighbors.

For each file in the exchange, open it and answer one question: **does anything in it bind
to the old framework?**

| Marker | Verdict |
|---|---|
| Only `Microsoft.IdentityModel.*`, `System.Text.Json`, `System.Security.Claims`, the app's own types | **Portable.** Branch A |
| Web-host types — the request, the response, the controller base, the pipeline context | **Coupled.** Branch B |
| Legacy data-access types, including exception types from the old ORM | **Coupled.** Branch B — and read step 4, this one hides |
| Configuration or DI types from the old host | **Coupled.** Branch B |
| Nothing framework-bound, but it references a type from another excluded folder | **Portable, blocked.** Branch A, after that folder |

The last row is the one that derails schedules. Un-excluding the exchange folder typically
does not compile on the first try, because the exchange depends on configuration, auditing,
or entity types that the same glob excluded for their own reasons. Enumerate the closure
before estimating; each of those neighbors gets its own classification pass, and some of
them are genuinely coupled even though the exchange is not.

### Step 3: Branch A — Move Portable Files Unchanged

For every file classified portable: **change the file's location, not its contents.**

Resist, specifically, all of the following. Each is a plausible cleanup, and each removes a
control:

- Collapsing the per-issuer validator hierarchy into one validator with a `switch`. The
  hierarchy is what keeps one issuer's claim rules from being applied to another issuer's
  token.
- Replacing the exchange with a bearer scheme and an authorization policy. A policy runs
  after authentication succeeded and cannot express "reject before matching."
- Simplifying the two-valued result type — outcome plus whether the reason may be disclosed
  — into a plain error message. That collapses the disclosure matrix in step 6.
- Turning sequential claim checks into a single LINQ predicate. Order is load-bearing; the
  matrix depends on which check ran first.
- "Fixing" a check that appears redundant with one the token validator already performed.
  Validating the signature proves the issuer minted the token. It proves nothing about
  *which workload* the token was minted for, which is what these checks establish.

If the file compiles for the new target with no edits, the migration of that file is done.
Say so explicitly in the summary rather than leaving it looking unfinished.

### Step 4: Branch B — Port the Coupled Seams

Four seams recur. Port the seam; preserve the control it wraps.

#### The endpoint

The exchange is reached through a controller or handler bound to the old web host. Port it
to the new host's endpoint model, and carry two things across that a mechanical port drops:

- **The challenge suppression.** An unauthorized response from an exchange endpoint must not
  trigger the application's interactive sign-in. On the old host that is usually an explicit
  challenge for the exchange's own scheme, which exists solely to stop the default scheme
  from redirecting. On the new host that call has no equivalent and needs none: write the
  401, the `WWW-Authenticate` header, and the body directly. Verify with an unauthenticated
  request: the correct response is a 401 carrying the challenge header, not a 302 to a login
  page.
- **The anonymous, self-validating boundary.** An exchange endpoint authenticates the request
  *itself* from the presented token, and commonly rejects one that arrived already carrying
  an ambient session. Keep it anonymous. **Do not port the challenge by naming a scheme in
  the endpoint's authorization metadata** — it breaks the endpoint both ways. A
  challenge-only scheme fails authorization, so the endpoint never runs and no exchange is
  possible. A validating scheme populates the caller principal, so a valid exchange is
  rejected as an ambient session. Keeping the anonymous marker beside that metadata is not a
  safe middle either: ASP.NET Core authenticates the named schemes *before* it honours the
  marker, and when none succeeds it assigns an empty principal — silently clearing the very
  session the endpoint meant to reject.
- **The response contract.** Status codes, the `WWW-Authenticate` header, and the body shape
  are a published API. Clients parse them.

#### The header collection

Request headers often reach deep into the exchange, as a legacy collection type in an
interface signature. That type is available on modern targets, so **this seam does not
produce a compile error** — which is exactly why it survives migrations untouched.

Convert at the boundary and keep the core in a neutral type:

```csharp
public interface ITokenExchangeService
{
    Task<ExchangeResult> ExchangeAsync(
        string subjectName,
        string token,
        IReadOnlyDictionary<string, string> requestHeaders);
}
```

Do not thread the host's own header abstraction through instead. That trades one host
coupling for another and leaves the core untestable without a request.

#### Data access inside the validators

Validators in this shape frequently **write to the database during token evaluation** — to
bind an identifier on first use, or to record that a policy matched. That is not a layering
mistake to be refactored away; the write is part of the trust decision.

Two consequences:

- The old ORM's concurrency exception type is caught inside the validator. Port the catch to
  the new ORM's equivalent. **A concurrency conflict here is expected, not exceptional** —
  two CI jobs from the same workflow can race on first use — and the handler after the catch
  re-reads the stored policy and confirms the concurrent write bound the *same* identifiers.
  Dropping that re-read turns a benign race into a trust bypass.
- Validators therefore hold a repository and must be registered with a request-scoped
  lifetime. See step 5, which is where this collides with caching.

#### Configuration and auditing

The exchange's configuration binder and its audit sink are usually themselves in excluded
folders. The audit records are not logging: they record which policy was compared against
which token and what the outcome was, and they are the only forensic trail an exchange
leaves. Port them in the same change, or the exchange lands with no evidence of its own
decisions.

### Step 5: Place Lifetimes and Dependencies

Registration moves from the old container configuration to the new host's service
collection. Two lifetimes matter, and they are different:

| Component | Lifetime | Why |
|---|---|---|
| Per-issuer metadata manager | **Singleton** | It caches discovery metadata and signing keys with its own refresh interval. One per issuer, held for the process lifetime. |
| Validators | **Scoped** | They hold repositories and write during evaluation. |

**Never construct a metadata manager inside a validation method.** A manager built per
request re-downloads the issuer's discovery document and key set on every call, which
defeats its cache, adds a network round trip inside the request, and turns the issuer's
availability into the endpoint's availability. Inject it:

```csharp
public sealed class WorkloadTokenValidator
{
    private readonly IIssuerMetadataCache _metadata;

    public WorkloadTokenValidator(IIssuerMetadataCache metadata)
    {
        _metadata = metadata ?? throw new ArgumentNullException(nameof(metadata));
    }
}
```

This differs from a fixed-authority bearer scheme, where the framework builds and holds one
manager per scheme and the application configures an authority instead. An exchange selects
its issuer per request, so it owns the cache — one entry per issuer, resolved by issuer
identity, held in a singleton. The rule *never construct one per request* is the same on
both sides.

### Step 6: Verify Against the Behavior-Preservation Checklist

## Behavior-Preservation Checklist

Every row is a control that a compiling, authenticating rewrite can drop. Confirm each one
survived, and write the list into the pull request description.

- **Per-issuer applicability, before any claim is read.** Each validator declines a policy
  that belongs to a different issuer, returning a "not mine" verdict distinct from a
  rejection. One validator is selected from the token's issuer, and every policy the caller
  owns is then offered to that one, so this guard is what keeps one issuer's claim rules off
  another issuer's stored policy. Dropping it is silent: every legitimate caller still
  authenticates, and what changes is that the wrong policy's criteria get read.
- **Required-claim gate.** Every claim the issuer's protocol guarantees is confirmed present
  before any policy is compared. A token missing one is rejected, not treated as a
  non-match.
- **Deny-list of trigger values.** The configured list of forbidden trigger or event values
  still rejects a token, **even when every other claim matches the policy**. This is the
  control that stops an untrusted contribution from publishing.
- **Claim matching does not run unless token validation succeeded.** Signature, issuer,
  audience, and lifetime validation gate the policy comparison. The evaluator returns on a
  validation error before it compares anything.
  - Reading the policy store *before* validating is not itself a defect, and it is common:
    the lookup key usually comes from the request body, not the token. **Do not "fix" it.**
    The property to preserve is that *matching* is gated, not that the store is untouched.
- **Exact-match claim comparison, with the original comparison semantics.** Identifier
  claims compared ordinally stay ordinal; name claims compared case-insensitively stay
  case-insensitive. Silently widening either is an authorization bypass.
- **Staged error disclosure, as a matrix by category** — not a single before/after line. See
  the table below.
- **Replay prevention by persistence, not by inspection.** The token's unique identifier is
  **stored under a uniqueness constraint**, and the reuse is rejected when the insert
  violates it. Checking that an identifier claim is merely *present* is not replay
  prevention, and neither is an in-memory set.
- **First-use identifier binding.** A policy created against mutable names binds the
  issuer's immutable numeric identifiers the first time it matches, and compares those
  identifiers on every later use. Without it, deleting and recreating a resource under the
  same name inherits the trust policy.
- **Concurrency conflict on first-use binding is handled** by re-reading the stored policy
  and confirming the identifiers written by the concurrent request are identical.
- **Supplementary request-header validators still run when JWT validation failed**, and
  **cannot resurrect a failed token.** They contribute additional failures; they never clear
  an existing one.
- **Identity and ownership checks run after matching.** Checking whether the named account
  is in good standing *before* a policy matched leaks which accounts exist and which have
  policies.
- **Every account the credential depends on is state-checked, not just the caller.** The
  policy owner and the account the credential will act for are frequently different, and the
  latter is often an organization. Re-read it and check its state too. A scope
  re-verification does not cover this: it checks the permission relationship between the two
  accounts, not whether either is deleted, locked, or unconfirmed — so a caller in good
  standing still passes it for an owner that is not.
- **The exchange endpoint stays anonymous and self-validating.** It authenticates from the
  presented token rather than from host authorization metadata, and any rejection of a
  caller who arrived already authenticated still fires. Adding an authorization requirement
  to select a challenge scheme removes that rejection with no visible symptom.
- **Bounded credential lifetime, and its hard ceiling.** The issued credential keeps its
  configured short duration, and the constant that the configured value may not exceed
  survives as code. It is not promoted to the inbound token's lifetime, and not to the
  application's default credential lifetime.
- **The issued credential's scopes are re-verified** against the caller's current
  permissions before it is returned.
- **Audit records** for the external credential, each policy comparison, the rejected
  replay, and the successful exchange all still get written.

### The Disclosure Matrix

An exchange endpoint is an enumeration oracle if it explains too much. It is unusable if it
explains nothing. Real implementations stage disclosure **by error category**, and a
migration that flattens this to a single rule breaks correct behavior in one direction or
the other.

| Failure category | Disclosable to the caller? |
|---|---|
| A required claim is absent, and the check runs before any policy is consulted | **Yes** — the token is malformed for its own issuer; this says nothing about what policies exist |
| A required claim is absent, or an asserted value is wrong, inside per-policy evaluation | **It depends on the implementation, and you must not normalize it** — see below |
| Token signature, issuer, audience, or lifetime invalid | **Yes** — a generic validation failure |
| The claimed owner or resource does not match any policy | **No** — this is the enumeration surface |
| Trust policy's first-use window expired | **Yes** — the caller owns the policy and must renew it |
| Trigger or event value is on the deny-list | **Yes** — but only *after* owner and resource matched |
| Workflow, environment, or branch does not satisfy the policy | **Yes** — after owner and resource matched |
| The named account or owner is in a state that forbids issuance | **Yes** — after a policy matched |

The dividing line is **ownership**, not sequence: once the request has demonstrated it knows
the owner and resource, the caller has proven enough to be told why the rest failed. Before
that point, only failures that are self-evident from the token are disclosable.

Note what the **first-use window** row does *not* say. A policy that has not yet bound its
immutable identifiers is in the **normal first-use success path**, not a failure — it binds
them during this very request. Only the expiry of that window is a failure. Treating "not
yet bound" as a rejection breaks every policy's first call, and it is an easy misreading to
write into a port because the two states are represented by the same nullable fields.

**The per-policy row is the one to be careful with, and it is why this is a matrix rather
than a rule.** Per-policy evaluation runs in a loop over the caller's policies, and
disclosable errors are collected across that loop. A category marked disclosable therefore
emits one message per policy, which reveals how many policies the named account holds for
that issuer and, in aggregate, what they are scoped to.

Implementations make this choice **per validator, on purpose, and they do not all choose the
same way.** In the worked example one issuer's validator marks its required-claim failures
disclosable, while another marks every failure non-disclosable including missing claims.
Read as an inconsistency, that is exactly the kind of thing a port tidies up — and
normalizing it in either direction is a disclosure change that no test will catch. Copy the
flag from each validator as written, one validator at a time, and treat a difference between
two validators as intentional until whoever owns the endpoint says otherwise.

## Success Criteria

Verifiable when this skill completes:

- Every file in the exchange is classified portable or coupled, and the classification is
  stated in the summary with the marker that decided it.
- Files classified portable moved without content changes. Any exception is called out with
  the compile error that forced it.
- No validator constructs a metadata manager inside a validation method; the manager is
  injected and registered as a singleton, and validators holding repositories are scoped.
- The endpoint returns the same status codes, headers, and body shape it returned before,
  and an unauthorized request does not redirect to interactive sign-in.
- The core exchange interfaces carry no web-host type.
- Every row of the behavior-preservation checklist is confirmed, in writing, with the
  location that satisfies it.
- The disclosure matrix is preserved by category. A rewrite that made every failure
  disclosable, or every failure opaque, is a regression even though it authenticates
  correctly.
- The dependency closure of the exchange — configuration, auditing, entities — is either
  ported or explicitly deferred with the compile boundary named.

Confirmed by the operator after deployment, not by the agent:

- A valid workload token from a trusted publisher still receives a credential with the same
  scopes and duration.
- Replaying a token that already succeeded is rejected.
- A token from an untrusted owner receives the same non-committal error it received before.
- A token whose trigger value is on the deny-list is rejected even from a trusted publisher.
- The audit trail contains the same records for the same events.
