// Copyright (c) Microsoft Corporation. All rights reserved.

// Summary computations for the Dependencies tab.
//
// computeDepsMetrics walks per-project dependency data and produces metric
// totals (packages / assemblies / projectRefs / frameworkRefs / imports).
// It can be called with either the raw shape (`dependencies.packages` arrays
// + `imports` array) OR a pre-aggregated shape (`packageCount` etc.). When
// the raw arrays are present we use them; otherwise we fall back to the
// pre-computed counts. This keeps the helper robust whether it's handed
// extension.mjs's normalized snapshot OR a raw dependencies-health.json
// payload.
//
// computeCompatibilityBreakdown sums compatibility values across all dep
// types (packages + assemblies + projectReferences + frameworkReferences)
// into { valid, partial, incompatible, unknown } for the stacked bar.

import { pick, categorizeCompatibility } from "./deps.mjs";

const DEP_BUCKETS = [
	["packages", "Packages"],
	["assemblies", "Assemblies"],
	["projectReferences", "ProjectReferences"],
	["frameworkReferences", "FrameworkReferences"],
];

function getDependencies(proj) {
	if (!proj || typeof proj !== "object") return null;
	return pick(proj, "dependencies", "Dependencies") ?? null;
}

function getImports(proj) {
	if (!proj || typeof proj !== "object") return null;
	return pick(proj, "imports", "Imports") ?? null;
}

export function computeCompatibilityBreakdown(projects) {
	const breakdown = { valid: 0, partial: 0, incompatible: 0, unknown: 0 };
	if (!Array.isArray(projects)) return breakdown;
	for (const proj of projects) {
		const deps = getDependencies(proj);
		if (!deps || typeof deps !== "object") continue;
		for (const [k, K] of DEP_BUCKETS) {
			const arr = pick(deps, k, K);
			if (!Array.isArray(arr)) continue;
			for (const entry of arr) {
				if (!entry || typeof entry !== "object") continue;
				const c = pick(entry, "compatibility", "Compatibility", "targetCompatibility", "TargetCompatibility");
				const bucket = categorizeCompatibility(c);
				breakdown[bucket] = (breakdown[bucket] ?? 0) + 1;
			}
		}
	}
	return breakdown;
}

// Aggregate per-project metric counts. Prefers raw arrays when available so
// callers can pass either the pre-normalized state from extension.mjs OR
// the raw dependencies-health.json payload.
export function computeDepsMetrics(projects) {
	const metrics = { packages: 0, assemblies: 0, projectRefs: 0, frameworkRefs: 0, imports: 0 };
	if (!Array.isArray(projects)) return metrics;
	for (const proj of projects) {
		if (!proj || typeof proj !== "object") continue;
		const deps = getDependencies(proj);
		const imports = getImports(proj);

		// Packages: prefer raw array length, else fall back to packageCount.
		const pkgsArr = pick(deps, "packages", "Packages");
		metrics.packages += Array.isArray(pkgsArr) ? pkgsArr.length : (proj.packageCount ?? 0);

		const asmArr = pick(deps, "assemblies", "Assemblies");
		metrics.assemblies += Array.isArray(asmArr) ? asmArr.length : (proj.assemblyCount ?? 0);

		const refArr = pick(deps, "projectReferences", "ProjectReferences");
		metrics.projectRefs += Array.isArray(refArr) ? refArr.length : (proj.projectRefCount ?? 0);

		const fwArr = pick(deps, "frameworkReferences", "FrameworkReferences");
		metrics.frameworkRefs += Array.isArray(fwArr) ? fwArr.length : (proj.frameworkRefCount ?? 0);

		metrics.imports += Array.isArray(imports) ? imports.length : (proj.importsCount ?? 0);
	}
	return metrics;
}

