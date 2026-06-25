// Copyright (c) Microsoft Corporation. All rights reserved.

// Project XML parsing — extracts TargetFramework(s) from .csproj/.fsproj.
// Mirrors Dashboard.Core.Providers.Build.ProjectDiscovery.

const TARGET_FRAMEWORKS_RE = /<TargetFrameworks>(.*?)<\/TargetFrameworks>/s;
const TARGET_FRAMEWORK_RE = /<TargetFramework>(.*?)<\/TargetFramework>/s;
const OUTPUT_TYPE_RE = /<OutputType>(.*?)<\/OutputType>/s;
const SDK_ATTR_RE = /<Project[^>]*\sSdk="([^"]+)"/i;
const PROJECT_REF_RE = /<ProjectReference[^>]*\sInclude="([^"]+)"/gi;

export const SKIP_DIRS = new Set([".git", "node_modules", "bin", "obj"]);

export function readTargetFrameworks(xml) {
	const multi = TARGET_FRAMEWORKS_RE.exec(xml);
	if (multi) {
		return multi[1]
			.split(";")
			.map((s) => s.trim())
			.filter(Boolean);
	}
	const single = TARGET_FRAMEWORK_RE.exec(xml);
	if (single) {
		const v = single[1].trim();
		return v ? [v] : [];
	}
	return [];
}

// Extract project kind from XML. Returns Sdk attribute value when it's an
// SDK-style project (e.g. "Microsoft.NET.Sdk.Web"), otherwise the OutputType
// value (Exe / Library / WinExe), otherwise null.
export function readProjectKind(xml) {
	const sdk = SDK_ATTR_RE.exec(xml);
	if (sdk) return sdk[1].trim();
	const out = OUTPUT_TYPE_RE.exec(xml);
	if (out) return out[1].trim();
	return null;
}

export function isSdkStyle(xml) {
	return SDK_ATTR_RE.test(xml);
}

// Extract <ProjectReference Include="..."> paths. Paths are returned exactly
// as written in the csproj (typically relative paths with Windows backslashes).
// XML comments are stripped first so commented-out references don't appear.
export function readProjectReferences(xml) {
	if (typeof xml !== "string" || !xml) return [];
	// Strip XML comments (<!-- ... --> across lines).
	const stripped = xml.replace(/<!--[\s\S]*?-->/g, "");
	const out = [];
	let m;
	PROJECT_REF_RE.lastIndex = 0;
	while ((m = PROJECT_REF_RE.exec(stripped)) !== null) {
		const path = m[1].trim();
		if (path) out.push(path);
	}
	return out;
}
