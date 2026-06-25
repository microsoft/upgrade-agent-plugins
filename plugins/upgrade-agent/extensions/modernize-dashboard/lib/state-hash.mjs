// Copyright (c) Microsoft Corporation. All rights reserved.

// Stable-hash helpers for the SSE no-op detection. Excludes generatedAt and
// noisy diagnostics fields that change every snapshot.

export function sortedKeysReplacer(_key, value) {
	if (value && typeof value === "object" && !Array.isArray(value)) {
		const sorted = {};
		for (const k of Object.keys(value).sort()) {
			sorted[k] = value[k];
		}
		return sorted;
	}
	return value;
}

export function hashState(state) {
	const { generatedAt, diagnostics, ...rest } = state;
	const diagKey = diagnostics
		? {
				paths: diagnostics.paths,
				resolutionSource: diagnostics.resolutionSource,
				resolvedRepoRoot: diagnostics.resolvedRepoRoot,
				gitKind: diagnostics.gitKind,
				gitDir: diagnostics.gitDir,
			}
		: null;
	return JSON.stringify({ ...rest, diagnostics: diagKey }, sortedKeysReplacer);
}
