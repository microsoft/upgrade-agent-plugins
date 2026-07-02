// Copyright (c) Microsoft Corporation. All rights reserved.

// Activity entry formatting. Pure functions: take a parsed JSONL row, return
// a structured display entry. Handles both EventEnvelope wrappers (activity.jsonl)
// and flat changelog rows.

export const ACTIVITY_EVENT_LABELS = {
	task_started: { label: "Task started", kind: "task" },
	task_completed: { label: "Task completed", kind: "task" },
	task_failed: { label: "Task failed", kind: "task-failed" },
	file_modified: { label: "File modified", kind: "file" },
	file_created: { label: "File created", kind: "file" },
	file_deleted: { label: "File deleted", kind: "file" },
	file_renamed: { label: "File renamed", kind: "file" },
	commit_created: { label: "Commit", kind: "commit" },
	commit_amended: { label: "Commit amended", kind: "commit" },
	build_completed: { label: "Build completed", kind: "build" },
	build_session_completed: { label: "Build session completed", kind: "build" },
	phase_entered: { label: "Phase entered", kind: "phase" },
	branch_changed: { label: "Branch changed", kind: "branch" },
};

export function formatActivityEntry(raw) {
	const payload = raw && typeof raw.payload === "object" && raw.payload !== null ? raw.payload : null;
	const fields = payload ? { ...raw, ...payload } : raw;
	const ts = fields.timestamp ?? fields.ts ?? fields.time ?? null;
	const eventName = fields.event ?? fields.type ?? "unknown";
	const meta = ACTIVITY_EVENT_LABELS[eventName] ?? { label: eventName, kind: "other" };
	const detail = buildActivityDetail(eventName, fields);
	const entry = {
		timestamp: ts,
		event: eventName,
		label: meta.label,
		kind: meta.kind,
		taskId: fields.taskId ?? fields.task_id ?? null,
		detail,
	};

	// Preserve structured fields for grouped views
	if (meta.kind === "file") {
		entry.filePath = fields.path ?? fields.filePath ?? null;
		entry.linesAdded = fields.linesAdded ?? fields.lines_added ?? null;
		entry.linesRemoved = fields.linesRemoved ?? fields.lines_removed ?? null;
		entry.patchFile = fields.patchFile ?? fields.patch_file ?? null;
	}
	if (meta.kind === "commit") {
		entry.commitHash = fields.commitHash ?? fields.hash ?? null;
		entry.commitMessage = fields.commitMessage ?? fields.message ?? null;
		entry.commitFiles = fields.files ?? null;
	}

	return entry;
}

export function buildActivityDetail(eventName, e) {
	switch (eventName) {
		case "task_started":
		case "task_completed":
		case "task_failed": {
			const parts = [];
			const name = e.displayName ?? e.taskName ?? e.name;
			if (name) parts.push(name);
			else if (e.taskId) parts.push(e.taskId);
			if (e.reason) parts.push(`— ${e.reason}`);
			return parts.join(" ");
		}
		case "file_modified":
		case "file_created":
		case "file_deleted":
		case "file_renamed": {
			const p = e.path ?? e.filePath ?? "";
			const adds = e.linesAdded ?? e.lines_added;
			const dels = e.linesRemoved ?? e.lines_removed;
			let suffix = "";
			if (adds != null || dels != null) {
				suffix = ` (+${adds ?? 0} / -${dels ?? 0})`;
			}
			return `${p}${suffix}`;
		}
		case "commit_created":
		case "commit_amended": {
			const hash = (e.commitHash ?? e.hash ?? "").slice(0, 7);
			const msg = e.commitMessage ?? e.message ?? "";
			return hash ? `${hash} ${msg}` : msg;
		}
		case "build_completed": {
			const errs = e.errorCount ?? e.errors ?? 0;
			const warns = e.warningCount ?? e.warnings ?? 0;
			const total = e.totalProjects ?? e.total ?? null;
			const ok = errs === 0;
			const tail = total != null ? ` across ${total} project${total === 1 ? "" : "s"}` : "";
			return `${ok ? "succeeded" : "failed"} — ${errs} error${errs === 1 ? "" : "s"}, ${warns} warning${warns === 1 ? "" : "s"}${tail}`;
		}
		case "build_session_completed": {
			const total = e.totalProjects ?? null;
			const succeeded = e.succeededProjects ?? null;
			const failed = e.failedProjects ?? 0;
			const ok = failed === 0 && (total ?? 0) > 0;
			const tally = total != null
				? ` (${succeeded ?? 0}/${total} ok${failed ? `, ${failed} failed` : ""})`
				: failed
					? ` — ${failed} failed`
					: "";
			return `${ok ? "succeeded" : "failed"}${tally}`;
		}
		case "phase_entered": {
			return e.phase ?? e.name ?? "";
		}
		case "branch_changed": {
			const from = e.oldBranch ?? e.from ?? "?";
			const to = e.newBranch ?? e.to ?? "?";
			return `${from} → ${to}`;
		}
		default: {
			const { timestamp, ts, time, event, type, taskId, task_id, ...rest } = e;
			const keys = Object.keys(rest);
			if (keys.length === 0) return "";
			if (keys.length <= 3) {
				return keys.map((k) => `${k}=${formatScalar(rest[k])}`).join(" ");
			}
			return JSON.stringify(rest);
		}
	}
}

export function formatScalar(v) {
	if (v == null) return "";
	if (typeof v === "string") return v;
	if (typeof v === "number" || typeof v === "boolean") return String(v);
	return JSON.stringify(v);
}
