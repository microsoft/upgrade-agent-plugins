// Copyright (c) Microsoft Corporation. All rights reserved.

// Parser for scenario-instructions.md — turns the markdown into a structured
// list of { sectionTitle, items: [...] } where each item is one of:
//   - { kind: "setting", label, value, raw }
//   - { kind: "text", text }
// Setting items are recognized from the canonical "- **Label**: value"
// pattern that the .NET upgrade agent emits.

// Strip a leading H1 since the panel itself has its own title.
const H1_RE = /^#\s+.+$/m;

// Section headers — H2/H3.
const HEADER_RE = /^(##{1,2})\s+(.+?)\s*$/;

// "  - **Key**: value" or "- **Key**: value". Also tolerates "- Key: value"
// without the bold, treating it the same way.
const SETTING_BOLD_RE = /^\s*-\s+\*\*([^*]+?)\*\*\s*[:：]\s*(.*\S)?\s*$/;
const SETTING_PLAIN_RE = /^\s*-\s+([A-Za-z][\w \-/]*?)\s*[:：]\s*(.*\S)?\s*$/;

// Bullet without "Key:" — keep as text so the section still shows the
// description (e.g., the "Execution Constraints" sub-bullets).
const PLAIN_BULLET_RE = /^\s*-\s+(.*\S)\s*$/;

export function parseScenarioInstructions(content) {
	if (typeof content !== "string" || !content.trim()) return [];
	const lines = content.replace(/\r\n/g, "\n").split("\n");
	// Drop the first H1 if present so the panel doesn't duplicate it.
	const startIdx = H1_RE.test(lines[0] ?? "") ? 1 : 0;
	const sections = [];
	let current = null;
	for (let i = startIdx; i < lines.length; i++) {
		const line = lines[i];
		const headerMatch = HEADER_RE.exec(line);
		if (headerMatch) {
			current = {
				level: headerMatch[1].length,
				title: stripInlineMarkdown(headerMatch[2]),
				items: [],
			};
			sections.push(current);
			continue;
		}
		if (!current) {
			// Stray paragraph before any header — fold into an unnamed leading section.
			if (line.trim() === "") continue;
			current = { level: 2, title: "", items: [] };
			sections.push(current);
		}
		const settingMatch = SETTING_BOLD_RE.exec(line) ?? SETTING_PLAIN_RE.exec(line);
		if (settingMatch) {
			current.items.push({
				kind: "setting",
				label: settingMatch[1].trim(),
				value: stripInlineMarkdown((settingMatch[2] ?? "").trim()),
				raw: line.trim(),
			});
			continue;
		}
		const bulletMatch = PLAIN_BULLET_RE.exec(line);
		if (bulletMatch) {
			current.items.push({
				kind: "text",
				text: stripInlineMarkdown(bulletMatch[1].trim()),
			});
			continue;
		}
		if (line.trim() !== "") {
			current.items.push({
				kind: "text",
				text: stripInlineMarkdown(line.trim()),
			});
		}
	}
	return sections;
}

// Look up a setting value by label, case-insensitive. Returns the first match
// or null. Used by the canvas to derive things like the current Flow Mode.
export function findSetting(sections, label) {
	if (!Array.isArray(sections) || typeof label !== "string") return null;
	const target = label.toLowerCase();
	for (const section of sections) {
		for (const item of section.items ?? []) {
			if (item.kind === "setting" && item.label.toLowerCase() === target) {
				return item.value || null;
			}
		}
	}
	return null;
}

function stripInlineMarkdown(s) {
	if (typeof s !== "string") return "";
	// Strip **bold**, *italic*, and `code` markers — we render values as plain text.
	return s
		.replace(/\*\*([^*]+?)\*\*/g, "$1")
		.replace(/(^|[^*])\*([^*\n]+?)\*(?!\*)/g, "$1$2")
		.replace(/`([^`]+?)`/g, "$1")
		.replace(/\\([\\`*_{}\[\]()#+\-.!])/g, "$1");
}
