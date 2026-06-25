// Copyright (c) Microsoft Corporation. All rights reserved.

// tasks.md parsing. Mirrors Dashboard.Core.Producers.TasksProducer.

export const TASK_EMOJI_MAP = [
	["✅", "Complete"],
	["🔄", "InProgress"],
	["🔲", "NotStarted"],
	["⚠️", "Skipped"],
	["❌", "Failed"],
];

export const TASK_LINKS_TRAILING_RE = /\s*\(\[(?:Content|Progress)\]\([^)]+\)(?:,\s*\[(?:Content|Progress)\]\([^)]+\))*\)\s*$/;

export function parseTaskLine(line) {
	if (!line || !line.trim()) return null;
	let trimmed = line.trimStart();
	if (trimmed.startsWith("- ")) {
		trimmed = trimmed.slice(2);
	}
	let state = null;
	let afterEmoji = null;
	for (const [emoji, st] of TASK_EMOJI_MAP) {
		if (trimmed.startsWith(emoji)) {
			state = st;
			afterEmoji = trimmed.slice(emoji.length).trimStart();
			break;
		}
	}
	if (!state || afterEmoji == null) return null;
	const colon = afterEmoji.indexOf(":");
	if (colon <= 0) return null;
	const id = afterEmoji.slice(0, colon).trim();
	let description = afterEmoji.slice(colon + 1).trim();
	description = description.replace(TASK_LINKS_TRAILING_RE, "");
	if (!id || !description || !/^\d/.test(id) || id.includes(" ")) return null;
	return { id, displayName: description, state };
}

export function getNumericPrefix(id) {
	const dash = id.indexOf("-");
	return dash > 0 ? id.slice(0, dash) : id;
}

export function getParentPrefix(prefix) {
	const lastDot = prefix.lastIndexOf(".");
	return lastDot > 0 ? prefix.slice(0, lastDot) : null;
}

export function assignParents(tasks) {
	const prefixToId = new Map();
	for (const t of tasks) {
		prefixToId.set(getNumericPrefix(t.id).toLowerCase(), t.id);
	}
	for (const t of tasks) {
		let parentPrefix = getParentPrefix(getNumericPrefix(t.id));
		while (parentPrefix) {
			const parent = prefixToId.get(parentPrefix.toLowerCase());
			if (parent && parent !== t.id) {
				t.parentId = parent;
				break;
			}
			parentPrefix = getParentPrefix(parentPrefix);
		}
	}
}

export function parseTasksOverview(content) {
	const lines = content.split(/\r?\n/);
	let inOverview = false;
	const out = [];
	for (const line of lines) {
		if (line.startsWith("## ")) {
			if (inOverview) break;
			if (/^##\s+Overview/i.test(line)) {
				inOverview = true;
				continue;
			}
		} else if (inOverview) {
			if (/\*\*Progress\*\*/i.test(line) || /<progress/i.test(line)) {
				continue;
			}
			out.push(line);
		}
	}
	const text = out.join("\n").trim();
	return text.length > 0 ? text : null;
}

// Parse the full contents of a tasks.md file into { tasks, overview }.
// `tasks` are flat (parentId computed but not nested).
export function parseTasksMd(content) {
	const tasks = [];
	let order = 0;
	for (const line of content.split(/\r?\n/)) {
		const parsed = parseTaskLine(line);
		if (parsed) {
			tasks.push({ ...parsed, order, parentId: null });
			order++;
		}
	}
	assignParents(tasks);
	return { tasks, overview: parseTasksOverview(content) };
}
