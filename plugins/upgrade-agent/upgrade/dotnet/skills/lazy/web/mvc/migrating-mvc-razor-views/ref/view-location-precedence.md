# Porting custom view-location precedence

Load this when Step 2 of `migrating-mvc-razor-views` found a custom view engine, display-mode selection, or explicit master-name calls.

## Contents

- [Map the collections](#map-the-collections)
- [Preserve display-mode selection](#preserve-display-mode-selection)
- [Configure Core](#configure-core)
- [When precedence depends on the request](#when-precedence-depends-on-the-request)
- [Verify the precedence](#verify-the-precedence)

## Map the collections

MVC exposes six location collections; ASP.NET Core exposes two. Views, partial views, and layouts resolved by name all probe the same list in Core:

| ASP.NET MVC | ASP.NET Core (`RazorViewEngineOptions`) |
|-------------|------------------------------------------|
| `ViewLocationFormats` | `ViewLocationFormats` |
| `PartialViewLocationFormats` | `ViewLocationFormats` |
| `MasterLocationFormats` | `ViewLocationFormats` |
| `AreaViewLocationFormats` | `AreaViewLocationFormats` |
| `AreaPartialViewLocationFormats` | `AreaViewLocationFormats` |
| `AreaMasterLocationFormats` | `AreaViewLocationFormats` |

The placeholders are unchanged — `{0}` view name, `{1}` controller name, `{2}` area name — so each format string ports almost as written. Core paths are application-root-relative: drop the leading `~` and keep the `.cshtml` extension, so `~/Views/{1}/{0}.cshtml` becomes `/Views/{1}/{0}.cshtml`. `{2}` is only bound for the area list; a non-area format containing it throws a format exception in MVC, so it belongs in the area list.

MVC's stock formats list every location twice, once as `.cshtml` and once as `.vbhtml`. Core Razor compiles C# only, so `.vbhtml` formats have no Core equivalent: drop them, and treat any `.vbhtml` view as a rewrite to `.cshtml` that has to happen before its location matters.

### The area list is a concatenation, not a copy

This is the one mapping that is not one-to-one, and getting it wrong stays invisible until a page renders the wrong file.

For a request inside an area, MVC searches **the area formats and then the non-area formats** — `VirtualPathProviderViewEngine` builds a single list from both. Core does not: an area request probes `AreaViewLocationFormats` alone. That is why Core's stock area list ends with `/Views/Shared/{0}.cshtml`, replicating a fallback MVC got from the other collection.

So the Core area list is the Framework area array **followed by** the Framework non-area array:

| Core collection | Source |
|-----------------|--------|
| `ViewLocationFormats` | the Framework non-area array |
| `AreaViewLocationFormats` | the Framework area array, then the Framework non-area array |

A path that repeats one already earlier in the merged list can be dropped — an earlier entry always wins, so the later copy never resolves — but dropping it is optional and keeping it is never wrong.

### When the engine list kept other engines

`ViewEngines.Engines.Insert(...)` and `.Add(...)` leave the existing engines in place. MVC asks each engine in registration order and each searches its own lists. For path-only Razor engines, flatten the base location lists in registration order, then preserve any display-mode selection as described below; arrays alone do not encode that selection:

| Core collection | Source, for engines E1, E2, … in registration order |
|-----------------|------------------------------------------------------|
| `ViewLocationFormats` | E1 non-area, then E2 non-area, … |
| `AreaViewLocationFormats` | E1 area, E1 non-area, then E2 area, E2 non-area, … |

A stock `RazorViewEngine` still in the list contributes MVC's C# defaults at its position: `~/Views/{1}/{0}.cshtml` and `~/Views/Shared/{0}.cshtml`, plus `~/Areas/{2}/Views/{1}/{0}.cshtml` and `~/Areas/{2}/Views/Shared/{0}.cshtml` for areas. The stock `WebFormViewEngine` contributes nothing, because Core has no equivalent.

Position is what goes wrong. After `Insert(0, custom)` the custom formats come **first**, so appending them to Core's pre-populated list — which already holds the stock defaults — puts `/Views/{1}/{0}.cshtml` ahead of them, and the custom engine never wins. After `Add(custom)` they come **last** and only answer names the stock engine missed. Keeping Core's defaults and appending custom formats is appropriate for this latter order, but first insert `/Views/{1}/{0}.cshtml` immediately before `/Views/Shared/{0}.cshtml` in the stock area list, after its two area-specific entries. Do not append that controller fallback after global shared. Clearing and writing out the complete flattened base-location list avoids depending on pre-populated entries; display modes still need the separate migration below.

### When the source orders diverge

Core distinguishes two lookup kinds, not six. `ViewLocationExpanderContext.IsMainPage` is `true` only for an action's main view, and the member that carries each lookup is fixed:

| Lookup | Core entry point | `isMainPage` |
|--------|------------------|--------------|
| An action's main view | `IViewEngine.FindView` / `GetView`, through `MvcViewOptions.ViewEngines` | `true` |
| A partial, or a view component's view | `IViewEngine.FindView` / `GetView`, through `MvcViewOptions.ViewEngines` | `false` |
| A layout | `IRazorViewEngine.FindPage` / `GetPage`, on the Razor engine that created the view | `false` |

So an expander separates at most two orders. The layout row matters when writing a custom engine: a layout lookup never reaches `MvcViewOptions.ViewEngines`, so an engine registered there to intercept layouts never fires.

Group the three non-area collections by the order each declares, then group the three `Area*` collections the same way, separately — `IsMainPage` does not depend on whether the request is in an area. Resolve the area group before concatenating the non-area array behind it; that appended array keeps its own grouping.

Explicit master calls need a rewrite even when all collections retain their stock values. Inspect MVC calls bound to `View(viewName, masterName)` and `View(viewName, masterName, model)`, including named arguments and wrappers. Move the selected layout to an explicit `Layout` path in the view or an appropriately scoped `_ViewStart`, preserving per-action layout choices and the original model or existing `ViewData.Model`. Then return the view without the master argument. Do not mechanically leave the two-string call unchanged: Core interprets its second argument as the model. Ordinary model overloads must remain model calls.

- **All three agree** — one static list reproduces them.
- **`ViewLocationFormats` differs from `PartialViewLocationFormats`** — branch an expander on `IsMainPage` and return each order.
- **`MasterLocationFormats` differs from the other two** — MVC consulted it only for a master name passed explicitly, as in `View(viewName, masterName)`. A Razor view's own `Layout` resolved against the page and never went through it. Core has no master-name overload, so each of those call sites has to change anyway: reference the layout by explicit path in the view or `_ViewStart`, and there is nothing left to port. Leave the master array out of the merge rather than widening the shared list with paths only explicit master names used.

Merging is a widening even when the orders agree, so it is never automatically safe. A path only one collection declared becomes eligible for every lookup sharing the merged list, so a file sitting at that path can answer a lookup MVC would have failed. Before merging, inventory the view names that exist at any path not declared by *all* the collections being merged. Each hit is a real behavior change to resolve — rename it, move it, reference it by explicit path, or accept it — not a hypothetical.

### When the engine did more than relocate files

`IViewLocationExpander` only supplies candidate paths to the Razor engine. It cannot reproduce an engine that changed what a view *is*.

- The custom engine only set `*LocationFormats`, or overrode `FindView` / `FindPartialView` to compute different **paths** — port it as formats, or as an expander.
- The custom engine overrode `CreateView` / `CreatePartialView`, returned a non-Razor `IView`, loaded content from a database or an embedded resource, or implemented `IViewEngine` from scratch — an expander carries none of that. Implement `IViewEngine` for Core and insert it into `MvcViewOptions.ViewEngines`, or supply the content through a custom file provider if only the *source* of the `.cshtml` changed.

Read the overridden members before choosing. A port that maps a content-loading engine onto an expander compiles, runs, and drops the behavior silently.

## Preserve display-mode selection

MVC's stock `DisplayModeProvider` tries `Mobile` for eligible requests and then the unsuffixed default. `DefaultDisplayMode` inserts its suffix before the extension: `Index.Mobile.cshtml` can beat `Index.cshtml` at the same location. Core does not apply these suffixes automatically.

Before flattening, inventory `DisplayModeProvider.Instance.Modes` in order, each `ContextCondition` or custom `IDisplayMode` transformation, browser overrides, `RequireConsistentDisplayMode`, and matching view, partial, and layout files. This applies even without a custom engine.

For name-based lookup, MVC checks eligible modes **within each location**, not all suffixed locations before all defaults. With stock Mobile/default modes and locations A then B, the order is `A/Index.Mobile.cshtml`, `A/Index.cshtml`, `B/Index.Mobile.cshtml`, `B/Index.cshtml`. A default file in A still beats a mobile file in B.

For independent suffix-based lookups, an `IViewLocationExpander` can expand each incoming location in eligible-mode order. In `PopulateValues`, record bounded, configured mode IDs in their effective order; never cache raw user-agent or header values. Preserve the source's request predicates and fallback policy, not just a new device heuristic.

**`RequireConsistentDisplayMode` needs resolution-aware state, not an expander alone.** `PopulateValues` runs before files are probed, so it cannot know which mode won. If `Index.Mobile.cshtml` is absent and MVC selects `Index.cshtml`, subsequent partial/layout lookups must honor the selected default mode even when `_Partial.Mobile.cshtml` exists. Preserve this with an integration that records the actual selected mode per request after successful resolution (including cache hits) and applies it to subsequent partial/layout lookups and their cache keys. Do not treat the eligible-mode list as the selected mode. If that integration is not available, require explicit approval for a behavior change rather than claiming parity.

An expander only supplies paths: preserve custom mode behavior and layout/explicit-path selection at their actual lookup entry points, since explicit paths bypass location expansion. Alternatively, obtain explicit approval to replace mode-specific views with responsive rendering and retire their selection rules.

Verify mobile, non-mobile, overlapping custom modes, and missing-suffix fallback for views, partials, and layouts, with cold and warm lookup caches. Include a higher-priority default file competing with a lower-priority suffixed file. With `RequireConsistentDisplayMode` enabled, also test a missing mobile main view alongside an existing mobile partial/layout: selecting the default main view must constrain the later lookups to default. Do not treat a successful build as selection parity.

## Configure Core

**Before (Framework — engine replaced during application start):**
```csharp
public static class ViewEngineConfig
{
    // Called from Application_Start, or from a PreApplicationStartMethod hook.
    public static void Register()
    {
        ViewEngines.Engines.Clear();
        ViewEngines.Engines.Add(CreateViewEngine());
    }

    private static RazorViewEngine CreateViewEngine()
    {
        var engine = new RazorViewEngine();

        engine.AreaMasterLocationFormats =
            engine.AreaViewLocationFormats =
            engine.AreaPartialViewLocationFormats =
            new[]
            {
                "~/Areas/{2}/Views/{1}/{0}.cshtml",
                "~/Overrides/Views/Shared/{0}.cshtml",
                "~/Areas/{2}/Views/Shared/{0}.cshtml",
            };

        engine.MasterLocationFormats =
            engine.ViewLocationFormats =
            engine.PartialViewLocationFormats =
            new[]
            {
                "~/Overrides/Views/{1}/{0}.cshtml",
                "~/Views/{1}/{0}.cshtml",
                "~/Overrides/Views/Shared/{0}.cshtml",
                "~/Views/Shared/{0}.cshtml",
                "~/Areas/Admin/Views/Accounts/{0}.cshtml",
            };

        return engine;
    }
}
```

**After (Core — the same paths in the same order, with the area list concatenated):**
```csharp
builder.Services.AddControllersWithViews()
    .AddRazorOptions(options =>
    {
        options.ViewLocationFormats.Clear();
        options.ViewLocationFormats.Add("/Overrides/Views/{1}/{0}.cshtml");
        options.ViewLocationFormats.Add("/Views/{1}/{0}.cshtml");
        options.ViewLocationFormats.Add("/Overrides/Views/Shared/{0}.cshtml");
        options.ViewLocationFormats.Add("/Views/Shared/{0}.cshtml");
        options.ViewLocationFormats.Add("/Areas/Admin/Views/Accounts/{0}.cshtml");

        options.AreaViewLocationFormats.Clear();
        options.AreaViewLocationFormats.Add("/Areas/{2}/Views/{1}/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Overrides/Views/Shared/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Areas/{2}/Views/Shared/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Overrides/Views/{1}/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Views/{1}/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Overrides/Views/Shared/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Views/Shared/{0}.cshtml");
        options.AreaViewLocationFormats.Add("/Areas/Admin/Views/Accounts/{0}.cshtml");
    });
```

`ViewLocationFormats` and `AreaViewLocationFormats` arrive **pre-populated with Core's defaults**. Appending to them leaves `/Views/{1}/{0}.cshtml` ahead of the override entry, so the override never wins and the migration looks successful. Call `Clear()` first and write the complete list in the recorded order — the flattened list, when the Framework kept other engines behind the custom one.

One more detail in that shape is easy to lose: the last non-area entry is a literal path into one area, letting non-area controllers share a view that lives there. It carries no `{2}`, it is not area-specific, and it keeps its position in both lists.

Views outside the standard `Views/` tree still have to be compiled. Any `.cshtml` inside an SDK-style web project is compiled by default, so an in-project override folder needs nothing extra. A referenced Razor class library needs nothing either — the SDK records it on the entry assembly and `ApplicationPartManager` discovers it from there. Reserve `AddApplicationPart` for an assembly outside that closure, such as one loaded dynamically at runtime. Override files dropped onto disk after deployment need the `Microsoft.AspNetCore.Mvc.Razor.RuntimeCompilation` package and `AddRazorRuntimeCompilation()`.

## When precedence depends on the request

Static formats cannot express a list that varies per request. If the Framework engine rebuilt its formats from a tenant, theme, or culture, port it as an `IViewLocationExpander`:

```csharp
public sealed class ThemeViewLocationExpander : IViewLocationExpander
{
    private static readonly string[] Themes = ["contoso", "fabrikam"];

    public void PopulateValues(ViewLocationExpanderContext context)
    {
        // Resolve the request to a member of a closed set. The raw value must never
        // reach this dictionary: these values form the view-lookup cache key, so an
        // attacker-chosen value both grows that cache without bound and arrives in
        // the format string below as a path segment.
        var requested = context.ActionContext.HttpContext.Request.Headers["X-Theme"].ToString();
        var theme = Themes.FirstOrDefault(candidate => string.Equals(candidate, requested, StringComparison.OrdinalIgnoreCase));
        if (theme is not null)
        {
            context.Values["theme"] = theme;
        }
    }

    public IEnumerable<string> ExpandViewLocations(ViewLocationExpanderContext context, IEnumerable<string> viewLocations)
        => context.Values.TryGetValue("theme", out var theme)
            ? new[] { $"/Themes/{theme}/Views/{{1}}/{{0}}.cshtml", $"/Themes/{theme}/Views/Shared/{{0}}.cshtml" }.Concat(viewLocations)
            : viewLocations;
}
```

Register it with `options.ViewLocationExpanders.Insert(0, new ThemeViewLocationExpander());` — position in that list decides which expander shapes the list first.

Two rules govern an expander, and both are about `PopulateValues`:

- **Everything the expansion varies on must be written there.** Those values form the view-lookup cache key, so a value read straight from the request inside `ExpandViewLocations` is resolved once and then served to every later caller whatever their request said.
- **Only bounded, validated values may be written there.** Because the values are the cache key, an unvalidated request value is an unbounded cache key; because they are interpolated into a path, an unvalidated value is a path traversal. Map the request onto a member of a closed set, as above, and write nothing when it matches nothing.

## Verify the precedence

Ordering defects do not fail a build. Verify with a view name that exists in two candidate locations: request the action, assert the higher-precedence file rendered, then move that file aside and assert the fallback renders.

Three cases need their own check, because each reaches the formats by a different route:

- **A view and a partial**, which shared one merged list in the port.
- **An action inside an area**, which no longer consults the non-area list unless the concatenation above was applied.
- **A layout referenced by bare name** (`Layout = "_Layout"`). This one changes direction between frameworks: MVC resolved a Razor page's `Layout` as a virtual path, and consulted `MasterLocationFormats` only for a master name passed to `View(viewName, masterName)`, whereas Core resolves a non-rooted layout name through `ViewLocationFormats`. A bare layout name that failed in MVC can now resolve. A layout path rooted at `~/` or `/`, or ending in `.cshtml`, resolves against the executing page in both frameworks and needs no change.
