// Copyright (c) Microsoft Corporation. All rights reserved.

// Dependency-health helpers. The C# DependencyHealthModels.cs has no
// [JsonPropertyName] attributes, so files can arrive as PascalCase from
// some producers. `pick()` does case-insensitive lookup.

export function pick(obj, ...names) {
	if (!obj || typeof obj !== "object") return undefined;
	for (const name of names) {
		if (Object.prototype.hasOwnProperty.call(obj, name)) {
			return obj[name];
		}
	}
	const lower = new Map();
	for (const key of Object.keys(obj)) {
		lower.set(key.toLowerCase(), key);
	}
	for (const name of names) {
		const k = lower.get(name.toLowerCase());
		if (k !== undefined) return obj[k];
	}
	return undefined;
}

const INCOMPAT_VALUES = new Set([
	"newVersionNeeded",
	"NewVersionNeeded",
	"notSupported",
	"NotSupported",
]);

export function countIncompatible(deps) {
	if (!deps) return 0;
	let count = 0;
	for (const key of ["packages", "assemblies", "projectReferences", "frameworkReferences"]) {
		const upper = key.charAt(0).toUpperCase() + key.slice(1);
		const arr = pick(deps, key, upper);
		if (!Array.isArray(arr)) continue;
		for (const entry of arr) {
			const c = pick(entry, "compatibility", "Compatibility", "targetCompatibility", "TargetCompatibility");
			if (INCOMPAT_VALUES.has(c)) {
				count++;
			}
		}
	}
	return count;
}

// Categorize a single dependency entry's compatibility into one of:
// 'valid', 'partial', 'incompatible', 'unknown'.
// Used by the Dependencies Summary breakdown bar.
export function categorizeCompatibility(value) {
	if (value === "valid" || value === "Valid") return "valid";
	if (value === "newVersionNeeded" || value === "NewVersionNeeded") return "partial";
	if (value === "notSupported" || value === "NotSupported") return "incompatible";
	return "unknown";
}
