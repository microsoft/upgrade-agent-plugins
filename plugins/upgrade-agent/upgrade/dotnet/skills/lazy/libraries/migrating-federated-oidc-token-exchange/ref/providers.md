# Provider Protocol Facts

Reference data for the workload issuers a token-exchange endpoint commonly trusts. These are
protocol facts about each identity provider, not application design decisions — the
application binding is a separate concern, shown in [the worked example](worked-example.md).

The generic rules live in `SKILL.md`. Read them first: the claim names below only make sense
once you know they are matched against a stored trust policy, in a specific order, with
staged disclosure.

Confirm every value below against the provider's own documentation before relying on it.
Issuers add claims, and self-hosted deployments change the issuer entirely.

## Why the claim names cannot be generic

The three providers below do not agree on a single claim vocabulary, and no subset is
common. A recipe written against one provider's claim names is wrong for the other two:

- GitHub Actions has an `event_name` claim carrying the workflow trigger. GitLab CI's
  equivalent is `pipeline_source`, under a different name and with a different value
  vocabulary. Entra has neither, because a service principal has no trigger.
- GitHub identifies a resource with `repository`; GitLab with `project_path`; Entra with
  `oid` inside a `tid`.
- Everything has a token identifier — but it is `jti` for two of them and `uti` for the
  third.

This is why the required-claim gate belongs to the provider layer, and only the *shape* of
the gate belongs to the generic recipe.

## GitHub Actions

| Fact | Value |
|---|---|
| Authority | `token.actions.githubusercontent.com` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Metadata address | `https://token.actions.githubusercontent.com/.well-known/openid-configuration` |
| Audience | Chosen by the relying application; the workflow requests it explicitly |
| Token identifier claim | `jti` |
| Issuer validation | Single fixed issuer string |

Matchable claims:

| Claim | Meaning | Stability |
|---|---|---|
| `repository_owner` | Account or organization name | **Mutable** — accounts can be renamed |
| `repository` | `owner/name` | **Mutable** |
| `repository_owner_id` | Numeric account identifier | **Immutable** |
| `repository_id` | Numeric repository identifier | **Immutable** |
| `event_name` | Workflow trigger, e.g. `push`, `release`, `pull_request_target` | n/a — deny-list dimension |
| `job_workflow_ref` | `owner/repo/.github/workflows/file.yml@ref` | Identifies the exact workflow file and ref |
| `environment` | Deployment environment name, when the job declares one | Present only for environment jobs |
| `ref` | Git ref the run was triggered on | |

Two consequences for the migration:

- **The name/identifier pair is why first-use binding exists.** A policy authored against
  `repository_owner` and `repository` is authored against renameable strings. Binding
  `repository_owner_id` and `repository_id` on first successful match, and comparing those
  from then on, is what stops a deleted-and-recreated repository from inheriting the trust.
- **`event_name` is the deny-list dimension.** Triggers such as `pull_request_target` and
  `issue_comment` can be caused by someone who cannot merge code. Rejecting a configured set
  of trigger values — *even when the repository claims match the policy exactly* — is a
  distinct control from claim matching, and it is the one most likely to be dropped by a
  rewrite because the token is otherwise entirely legitimate.

## GitLab CI

| Fact | Value |
|---|---|
| Authority | `gitlab.com` |
| Issuer | `https://gitlab.com` |
| Metadata address | `https://gitlab.com/.well-known/openid-configuration` |
| Audience | Chosen by the relying application |
| Token identifier claim | `jti` |
| Issuer validation | Fixed per instance — **a self-managed instance issues under its own host name**, so an application that accepts self-managed GitLab needs a per-instance issuer entry rather than one constant |

Matchable claims:

| Claim | Meaning | Stability |
|---|---|---|
| `namespace_path` | Group or user namespace | **Mutable** |
| `namespace_id` | Numeric namespace identifier | **Immutable** |
| `project_path` | Full path including namespace | **Mutable** |
| `project_id` | Numeric project identifier | **Immutable** |
| `ref` | Git ref the pipeline ran on | |
| `ref_type` | `branch` or `tag` | |
| `pipeline_source` | What started the pipeline, e.g. `push`, `merge_request_event`, `schedule`, `web`, `trigger` | Always present |
| `environment` | Deployment environment, when the job declares one | Present only for environment jobs |

GitLab has the same mutable/immutable pairing as GitHub, so first-use binding applies
identically.

**`pipeline_source` is GitLab's trigger dimension** — the claim that corresponds to GitHub's
`event_name`, and therefore the one a deny-list would be expressed against. Nothing in
GitHub's vocabulary suggests the name, which makes it easy to conclude that GitLab has no
trigger claim at all.

Two errors follow from that conclusion, in opposite directions. If the implementation being
ported *does* consume it, a claim-for-claim mapping finds no home for the check and drops
it. If it *does not*, the temptation is to substitute the nearest-looking claim — mapping
`event_name` onto `ref_type`, since both read as "what kind of thing triggered this" — which
is worse than dropping it, because it leaves a control that looks present: `ref_type`
distinguishes a branch from a tag, and says nothing about whether the pipeline came from a
trusted push or from an untrusted contributor's merge request.

Check which claims the implementation in front of you actually reads before deciding either
way. Preserving a control it never had is as much a behavior change as losing one it did.

## Microsoft Entra service principal

| Fact | Value |
|---|---|
| Authority | `login.microsoftonline.com` |
| Issuer (configured) | `https://login.microsoftonline.com/common/v2.0` |
| Metadata address | `https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration` |
| Audience | The application's own registered audience |
| Token identifier claim | **`uti`, not `jti`** |
| Issuer validation | **Not a string comparison** — see below |

Matchable claims:

| Claim | Meaning |
|---|---|
| `tid` | Tenant identifier (GUID) |
| `oid` | Object identifier of the service principal (GUID) |
| `sub` | Subject; for this shape it must equal `oid` |
| `azpacr` | Client credential type used to obtain the token |
| `idtyp` | Identity type; `app` for an application identity |
| `ver` | Token version |

Three things differ from the CI providers, and each has bitten a migration:

- **The token identifier is `uti`.** Replay prevention keyed on `jti` silently stops working
  for Entra tokens, because the claim is absent — and "absent identifier" reads as "nothing
  to check" rather than as an error unless the required-claim gate covers it.
- **Issuer validation is tenant-aware.** The configured issuer is the multi-tenant
  `common` endpoint, but a real token's `iss` is tenant-specific. Validating with a plain
  string comparison against `common` rejects every valid token; validating with no issuer
  check at all accepts tokens from every tenant in the world. The correct form is the
  tenant-aware issuer validator from the Entra identity libraries, combined with an
  application-owned **tenant allow-list**. Signing-key issuer validation must also be
  enabled, which is what stops one tenant's key from signing another tenant's issuer.
- **Assertion claims, not just matching claims.** `azpacr`, `idtyp`, and `ver` are not
  compared against the policy — they are asserted to have specific values, which is how the
  application requires a certificate-backed or managed-identity application token rather
  than a user token or a client-secret token. A migration that keeps only the claims
  appearing in the trust policy drops these, and the endpoint starts accepting weaker
  credential types with every policy still matching correctly.

## Adding a provider

A new issuer needs all of:

1. Issuer authority and metadata address, and a **singleton** metadata cache entry keyed by
   issuer.
2. An audience the application controls.
3. A token identifier claim for replay persistence — confirm which one; do not assume `jti`.
4. The required-claim list for the gate.
5. The mutable/immutable claim pairs, if the provider has them, for first-use binding.
6. Whichever assertion claims constrain the credential type.
7. A decision on which failures are disclosable, slotted into the matrix in `SKILL.md`.

Items 3, 5, and 6 are the ones most often missed, because a provider integration that omits
them still authenticates successfully for the happy path.
