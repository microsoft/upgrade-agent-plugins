---
name: migrating-webapi-odata
description: >
  Gates ASP.NET Framework to Core migrations on externally-consumed wire
  contracts before migrating Web API OData to Microsoft.AspNetCore.OData.
  Use when replacing legacy OData or migrating Atom feeds, custom
  ODataEntityTypeSerializer implementations, or non-OData JSON/XML endpoints with pinned response shapes
  or explicit repository compatibility hints, even without an OData package.
  Not for version bumps that retain the existing stack or applications already
  on ASP.NET Core.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ASP.NET Web API OData Migration Compatibility Gate

## Overview

Run this gate before changing packages, formatters, serializers, models, or
route ownership. Start with the applicability check, not a full endpoint census.
An externally-consumed wire contract includes callers outside
the coordinated migration, even on a private network. No in-repo client does
not mean no external consumer.

`Microsoft.AspNet.WebApi.OData` 5.x serves OData v3;
`Microsoft.AspNet.OData` serves OData v4. `Microsoft.AspNetCore.OData` is v4-only,
and ODataLib 7 dropped Atom support. An API rename or matching EDM model cannot
preserve a v3/Atom protocol contract.

## Workflow

- [ ] Check whether the change can affect an HTTP wire contract
- [ ] Inventory wire contracts, including non-OData endpoints
- [ ] Record a PASS or STOP for the intended migration scope
- [ ] Choose preservation on STOP; load the v4 recipe only after PASS
- [ ] Verify wire conformance before moving traffic

## Applicability Check

Reuse the task's project/usage inventory. Inspect the affected output paths and
their consumers, including dependent Framework hosts when changing a library.
The gate applies to OData/Atom feeds, JSON/XML responses, other explicitly
versioned HTTP response shapes, or repository/user hints requiring preservation.
No OData package alone is not proof of non-applicability.

If evidence establishes that the affected scope has no such surface or
dependent host, record NOT APPLICABLE with that evidence and return to the
calling workflow without the full inventory or v4 recipe. This includes a
Razor-views-only change with no API/raw-response actions, contract-bearing
formatter/model dependencies, or preservation hints. HTML pages still serve
HTTP; their mere presence does not require a serialization-contract census.
Unknown output paths or consumers require the full gate, not this shortcut.

## Step 1: Inventory Wire Contracts

Inspect the Framework host and its referenced response-model/serialization
libraries, configuration, tests, API documentation, and explicit repository
hints. Include C# and Visual Basic registrations and inherited serializers.
Do not exit early when no OData package or controller is found.

Record the current Project Approach and which runnable Framework host will
retain protected endpoints. Run the inventory before retargeting the project;
if the approach or retained host is unknown, STOP and resolve that evidence.

Extend the calling Framework migration's Baseline Capture instead of making a
second endpoint list. Keep its status codes, auth rules, and custom headers
for final verification; add the fields below for the gate decision. Reuse a
current baseline with evidence, filling gaps rather than replacing it.

For each affected endpoint, record method/URL, consumers, protocol version,
negotiated media types, formatter and serializer registration paths, and
baseline evidence with source locations. Trace registration helpers and
environment conditions to the effective configuration; a text search is only
discovery, not proof of absence.

For non-OData JSON/XML, use documented schemas, contract tests, client bindings,
or representative captured responses to fingerprint the original shape:
field names and casing, types, nullability, nesting, XML namespaces/attributes,
and element ordering where meaningful. Inspect `JsonProperty`, `DataMember`,
`XmlElement`, naming policies, custom converters, and raw response writers.
A DTO's CLR names alone are not a response fingerprint. Treat incomplete
consumer, registration, or schema evidence as unknown, not compatible.

## Step 2: Apply the Mandatory Compatibility Gate

Evaluate every signal below independently, including when OData is absent.
Any present signal means STOP automated migration for the affected scope.

| Signal | Detection evidence | Decision |
| --- | --- | --- |
| Atom formatters | The effective formatter set is Atom-only (including when clearing/replacing defaults leaves only Atom-capable formatters), or consumers require `application/atom+xml`; trace `ODataMediaTypeFormatters.Create()`, `SupportedMediaTypes`, and registration helpers. Clearing defaults then registering JSON-only formatters is not an Atom signal. | STOP |
| Custom OData serializer | A direct or indirect `ODataEntityTypeSerializer` subclass, or a serializer-provider registration selecting one, customizes the existing response. Inspect overrides and registration even if the CLR model is unchanged. | STOP |
| Pinned non-OData shape | A JSON/XML schema fingerprint, contract test, or client binding pins response field names/types or XML structure for an externally-consumed endpoint, including raw MVC/Web API responses. | STOP |
| Explicit repository hint | Repository documentation, instructions, or user-provided contract evidence requires preserving a response shape or protocol for existing consumers, even with no OData, formatter, or serializer match. | STOP |

STOP also when evidence is unknown or an externally-consumed OData v1-v3
protocol is still required, including JSON-only feeds. Absence of Atom is not
evidence that v3 JSON can become v4 JSON.

Record PASS only when all four signals are absent, the inventory is complete,
and the source protocol and required response contract are supported by the
target. Persist the scope, each signal's present/absent/unknown result, evidence
locations, unresolved questions, decision, and preservation choice as described
in Gate Records below. An obsolete-package warning, a successful build, or owner approval to
investigate is not a PASS.

## Gate Records

In a managed task, write the inventory and per-scope evidence under
`## Wire Compatibility` in `progress-details.md`; put the verdict and a relative
link to that section in `task.md`. Keep the executor return compact: decision,
blocked scope, and record path, not the full inventory.

Record the owner's preservation choice and approved Project Approach changes
immediately in `scenario-instructions.md` through the existing workflow, with
the affected scope and evidence link. Do not imply approval that was not given.
For a direct invocation without task state, use
`.github/upgrades/wire-compatibility.md` for the scoped evidence and decisions;
link that record when a managed scenario is later created.

On resume, read these records first; reuse still-current evidence and the
recorded owner decision. Re-evaluate only changed or unresolved scope, and ask
again only when the required decision changes or was never recorded.

## Step 3: Preserve or Migrate

On STOP, do not remove the OData v3 packages or their shared/transitive
dependencies. Keep the live host's formatter, serializer, model, and route
registrations intact. Do not install a v4 replacement or change response
serialization as an automatic fix.

For an **in-place** plan, STOP the entire host conversion before retargeting,
SDK conversion, package replacement, or endpoint edits. Preserving a route
inside the same project being converted does not preserve a runnable Framework
host. Request owner-approved replanning to a separately hosted side-by-side
preservation scope before proceeding, whether the chosen path is YARP or raw
MVC. Do not silently change confirmed options. Through the existing planning
workflow, update the Project Approach, task scopes, and dependencies so the
original Framework host remains runnable while the Core candidate is built.
A PASS for another endpoint in that host does not authorize in-place conversion.
If conversion already started, pause further changes and request an approved
recovery plan for the original host; do not claim the preservation path is ready.

Recommend keeping the endpoint on the Framework host behind YARP by default.
Alternatively, agree a separately scoped hand-rewrite as raw ASP.NET Core MVC
returning the original content shape, status, content type, headers, and query
behavior; do not substitute an OData v4 controller. Raw MVC is not an automatic
protocol emulator: preserve metadata, paging/continuation links, errors, and
batch semantics if consumers use them, or keep those operations proxied.
Ask the owner to choose the preservation path before implementation. Keep the
Framework endpoint and its dependencies until the replacement is proven and
cutover is separately approved; choosing MVC does not turn STOP into PASS.

On PASS with OData usage, read [the v4 migration recipe](ref/v4-migration.md)
and apply it only to that scope. On PASS without OData usage, return the gate
result to the calling migration task; do not add an OData package.
If a protected endpoint shares packages or configuration with another endpoint,
split the migration scope rather than using the other's PASS to remove them.

## Step 4: Verify Before Moving Traffic

Compare the same representative requests against the original endpoint and
the candidate, not two URLs that both proxy to the original. Require matching
status, contract-relevant headers (including content type), and structural and
semantic JSON/XML bodies: names, types, namespaces, meaningful element order,
metadata, paging links, errors, and supported query/batch behavior. Document
any normalization for nondeterministic values; never normalize away shape drift.
Do not replay mutating requests against live state without side-effect isolation.

Dual-host response conformance complements this pre-migration gate: it catches
shape drift the inventory misses, but cannot waive a STOP or make OData v4
support a v3/Atom contract. Keep traffic on the original endpoint if conformance
is missing or fails. Route ownership alone does not establish wire compatibility.

## Decomposition Rules

Pins do not propagate to subtasks. Add `#skill:migrating-webapi-odata` to every
child task that converts or retargets the HTTP host project, or touches an affected
endpoint, response model/serializer, shared OData dependency, or traffic cutover,
including non-OData work. Carry the scoped
gate result, evidence link, and recorded preservation decision into the child
`task.md`; rerun the gate if evidence or
scope changes.

## Acceptance Examples

Use [the generic compatibility examples](ref/compatibility-examples.md) to
check the four independent stop signals, unknown evidence, and a valid PASS.
