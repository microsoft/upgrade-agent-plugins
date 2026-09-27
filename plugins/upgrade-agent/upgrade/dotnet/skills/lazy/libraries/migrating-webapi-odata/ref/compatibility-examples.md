# Generic Wire-Compatibility Acceptance Examples

Each case is an independent synthetic application. All unspecified signals
are absent with a complete inventory, except in the explicitly unknown case.
For every STOP, retain the original packages and registrations and recommend
YARP or a separately agreed raw MVC preservation task, not automatic OData v4.

| Case | Original evidence | Expected decision |
| --- | --- | --- |
| Atom-only feed | `/inventory/feed` registers only formatters selected by `SupportedMediaTypes` containing `application/atom+xml`; deployed clients request Atom. No custom serializer or repository hint exists. | STOP |
| Custom serializer | `/inventory/items` serves OData v4 JSON, but `InventorySerializer` indirectly inherits `ODataEntityTypeSerializer` and overrides `CreateEntry` to append a property. No Atom formatter, non-OData contract, or hint exists. | STOP |
| Pinned JSON response | `/api/stock` is non-OData; a client schema requires `{"item_code":"B7","units_available":4}`. The candidate emits `{"itemCode":"B7","unitsAvailable":"4"}`. No OData package, custom serializer, or hint exists. | STOP |
| Pinned XML response | `/api/stock.xml` is non-OData; a contract test pins `<stock xmlns="urn:inventory"><code>B7</code><units>4</units></stock>` and that child order. Dropping the namespace or swapping children violates it. | STOP |
| Repository hint only | `api-contract.md` states: "External device clients require the current `/devices/status` response names and types; preserve the wire contract." No OData or customization is found; the hint alone blocks automatic conversion. | STOP |
| Unknown registration | A feed's effective formatter registration is inside an unavailable shared library. A local search found no Atom references, but cannot establish absence. | STOP |
| JSON-only v3 feed | `/inventory/v3` has external clients requiring OData v3 JSON and no Atom formatter or custom serializer. The target offers only v4. | STOP |
| In-place Atom feed | Project Approach is In-place. `/inventory/feed` still serves external Atom clients from the project about to be retargeted. Keep that Framework host runnable and request owner-approved side-by-side replanning before any project conversion. | STOP |
| In-place pinned JSON | Project Approach is In-place. `/api/stock` has a pinned external non-OData response contract. A proposed raw MVC rewrite still needs a separate Core candidate; do not retarget the original host under the unchanged plan. | STOP |
| Compatible v4 service | `/internal/catalog` uses `Microsoft.AspNet.OData`, stock OData v4 JSON formatters/serializers, and a complete consumer and schema inventory. All callers are in the coordinated upgrade, no shape is pinned, and the target supports the required contract. | PASS |
| Non-OData without a pinned contract | `/internal/health` uses ordinary MVC with a complete inventory, all callers in the coordinated upgrade, no customization or preservation hint, and a target-supported response contract. Return to the caller without installing OData. | PASS |
| JSON-only formatter replacement | A stock OData v4 service clears defaults then registers JSON-only formatters. Its complete inventory confirms no Atom clients, custom serializers, pinned non-OData shapes, or preservation hints; the target supports its contract. Clearing defaults alone is not an Atom signal. | PASS |
| Razor views only | The affected MVC site has only HTML view actions, no API/raw-response actions, no shared response-model/formatter dependencies, and no preservation hint. Existing inventory proves those boundaries. Skip the full census and return to the caller. | NOT APPLICABLE |
| Non-serving library | The changed JSON serializer writes local settings; the usage inventory proves no Framework HTTP host consumes its models or output. Skip the full gate without adding OData. | NOT APPLICABLE |
| Uncertain library consumers | A serializer library's consumers cannot be established. Absence of a web project in this checkout is not proof of no HTTP consumer. Full inventory remains incomplete. | STOP |

## Example Gate Record: Pinned JSON Response

- Scope: `GET /api/stock`, its response DTO and serializer configuration.
- Evidence: `contracts/stock.schema.json` requires `item_code: string` and
  `units_available: integer`; a device client consumes that schema.
- Signals: Atom absent; custom OData serializer absent; pinned non-OData shape
  present; explicit repository hint absent.
- Decision: STOP. Renaming both properties and changing a number to a string
  is contract drift even if both responses parse as JSON and return 200.
- Preservation: keep `/api/stock` behind YARP pending an owner-chosen raw MVC
  rewrite that emits the original names and types.

## Mixed Scope

If the compatible v4 service and the Atom feed share a Framework host, PASS
for `/internal/catalog` does not permit removing the feed's v3 packages,
formatters, shared central versions, or proxy route. Split their tasks and
carry each decision into its own children. Unknown ownership of a dependency
keeps that cleanup stopped.

For an in-place plan, that split must happen at the host/project level, not
only in the endpoint task list. Leave the original host unchanged, obtain
approval for side-by-side preservation, and update the plan before creating
the separate candidate. A previously approved in-place plan is not approval
for that change in approach.
