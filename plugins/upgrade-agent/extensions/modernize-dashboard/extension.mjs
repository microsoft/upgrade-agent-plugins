// Copyright (c) Microsoft Corporation. All rights reserved.

// Upgrade Dashboard canvas extension.
//
// Declares a single canvas (`dashboard`) and serves it via the shared
// HTTP/SSE server in lib/server.mjs. Artifact reading + snapshot composition
// live in lib/snapshot.mjs and are shared with the standalone CLI entry
// (bin/modernize-dashboard.mjs).

import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CanvasError, createCanvas, joinSession } from "@github/copilot-sdk/extension";

import { snapshot, resolveRepoRootFromDisk, readScenarios, getActiveScenario } from "./lib/snapshot.mjs";
import { createDashboardServer } from "./lib/server.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const INDEX_HTML_PATH = path.join(__dirname, "canvas", "index.html");

const VALID_PANELS = new Set([
	"overview",
	"activity",
	"scenario",
	"projects",
	"assessment",
	"dependencies",
	"tasks",
	"options",
	"diagnostics",
]);

// ---- Repo path resolution (session-aware) ----------------------------------
//
// The supported repo hint is `ctx.session.workingDirectory`, present on every
// canvas provider callback (open / action / close). We do NOT use
// `session.workspacePath` — that is the session's own artifact-storage dir
// (checkpoints/, plan.md, files/), not the repository root, and is unpopulated
// on the local CLI.

function resolveRepo(workingDirectory) {
	if (process.env.MODERNIZE_DASHBOARD_REPO) {
		return { path: process.env.MODERNIZE_DASHBOARD_REPO, source: "MODERNIZE_DASHBOARD_REPO env var", confident: true };
	}
	if (workingDirectory && existsSync(workingDirectory)) {
		return { path: workingDirectory, source: "session.workingDirectory", confident: true };
	}
	// Disk-walk is a provisional best-guess — no env var and no session cwd yet.
	return { ...resolveRepoRootFromDisk(), confident: false };
}

// ---- Bootstrap --------------------------------------------------------------

let session = null;
let resolvedRepo = null;

// Cache only a *confident* resolution (env var or session.workingDirectory). A
// disk-walk fallback is provisional: keep re-resolving so a later callback that
// carries a real session.workingDirectory can upgrade it, instead of being
// permanently shadowed by an early guess.
async function ensureResolvedRepo(workingDirectory) {
	if (resolvedRepo?.confident) return resolvedRepo;
	const next = resolveRepo(workingDirectory);
	if (next.confident || !resolvedRepo) resolvedRepo = next;
	return resolvedRepo;
}

function requireSession() {
	if (!session) {
		throw new CanvasError(
			"session_unavailable",
			"Copilot session is not yet available; try again shortly.",
		);
	}
	if (typeof session.send !== "function") {
		throw new CanvasError(
			"session_send_unavailable",
			"This Copilot CLI build does not expose session.send; agent-relay actions are unavailable.",
		);
	}
}

// ---- Action handler registry -----------------------------------------------

const actionHandlers = new Map();

async function getSnapshotForResolution(ctx) {
	const resolution = await ensureResolvedRepo(ctx?.session?.workingDirectory);
	if (!resolution) {
		throw new CanvasError("repo_unresolved", "Workspace repo not yet resolved.");
	}
	return snapshot(resolution.path, resolution);
}

actionHandlers.set("refresh", async ({ instanceId }) => {
	await dashboardServer.broadcastToInstance(instanceId, { force: true });
	return { ok: true, generatedAt: new Date().toISOString() };
});

actionHandlers.set("set_panel", async ({ input }) => {
	const panel = input?.panel;
	if (!VALID_PANELS.has(panel)) {
		throw new CanvasError("canvas_invalid_panel", `Unknown panel: ${panel}`);
	}
	return { ok: true, panel };
});

actionHandlers.set("switch_mode", async ({ input }) => {
	requireSession();
	const mode = input?.mode;
	if (mode !== "guided" && mode !== "automatic") {
		throw new CanvasError("invalid_mode", "mode must be 'guided' or 'automatic'.");
	}
	await session.send(
		`Please switch the upgrade mode to ${mode}. (Requested from the Upgrade Dashboard canvas.)`,
	);
	return { ok: true, status: `Asked the agent to switch to ${mode} mode.` };
});

actionHandlers.set("share_assessment_as_gist", async (ctx) => {
	requireSession();
	const state = await getSnapshotForResolution(ctx);
	const assessment = state.assessment;
	if (!assessment?.path) {
		throw new CanvasError(
			"no_assessment",
			"No assessment.json detected for the current scenario — nothing to share.",
		);
	}
	if (!existsSync(assessment.path)) {
		throw new CanvasError(
			"assessment_missing_on_disk",
			`assessment.json was indexed at ${assessment.path} but is no longer on disk.`,
		);
	}
	await session.send(
		`Create a *private* GitHub gist from the upgrade assessment at \`${assessment.path}\`. ` +
		`Use the gh CLI: \`gh gist create --private --filename assessment.json '${assessment.path}'\`. ` +
		`Report the resulting gist URL back when done. (Requested from the Upgrade Dashboard canvas.)`,
	);
	return { ok: true, assessmentPath: assessment.path };
});

actionHandlers.set("explain_dependency", async (ctx) => {
	requireSession();
	const packageName = (ctx.input?.packageName ?? "").toString().trim();
	if (!packageName) {
		throw new CanvasError("invalid_package", "packageName is required.");
	}
	const state = await getSnapshotForResolution(ctx);
	const pkg = state.dependencies?.packages?.find((p) => p.name === packageName);
	const tfm = state.dependencies?.targetFramework ?? "(unknown)";
	const compat = pkg?.isCompatible === false ? "incompatible" : pkg?.isCompatible === true ? "compatible" : "unknown";
	const rec = pkg?.recommendedVersion ? ` Recommended version: ${pkg.recommendedVersion}.` : "";
	await session.send(
		`Explain why the NuGet package \`${packageName}\` is reported as ${compat} for target framework \`${tfm}\` ` +
		`in the upgrade dependency report.${rec} Suggest concrete steps to upgrade or replace it. ` +
		`(Requested from the Upgrade Dashboard canvas.)`,
	);
	return { ok: true, status: `Asked the agent to explain ${packageName}.` };
});

actionHandlers.set("push_context", async (ctx) => {
	if (!session) {
		throw new CanvasError("session_unavailable", "Copilot session is not yet available; try again shortly.");
	}
	const api = session.rpc?.extensions?.sendAttachmentsToMessage;
	if (typeof api !== "function") {
		throw new CanvasError(
			"unsupported_runtime",
			"This Copilot CLI build does not expose session.extensions.sendAttachmentsToMessage; update the CLI to push dashboard context.",
		);
	}
	const state = await getSnapshotForResolution(ctx);
	const active = Array.isArray(state.scenarios)
		? state.scenarios.find((s) => s && s.id === state.activeScenarioId) ?? null
		: null;
	let taskSummary = null;
	if (state.tasks && Array.isArray(state.tasks.tasks)) {
		const counts = { complete: 0, inProgress: 0, notStarted: 0, skipped: 0, failed: 0 };
		const map = { Complete: "complete", InProgress: "inProgress", NotStarted: "notStarted", Skipped: "skipped", Failed: "failed" };
		for (const t of state.tasks.tasks) {
			counts[map[t?.state] ?? "notStarted"] += 1;
		}
		taskSummary = { total: state.tasks.tasks.length, ...counts };
	}
	const payload = {
		capturedAt: new Date().toISOString(),
		repoRoot: state.repoRoot,
		activeScenarioId: state.activeScenarioId,
		scenario: active
			? {
				id: active.id,
				description: typeof active.description === "string" ? active.description : null,
				targetFramework: active.properties?.UpgradeTargetFramework ?? active.properties?.upgradeTargetFramework ?? null,
			}
			: null,
		assessment: state.assessment
			? { path: state.assessment.path, counts: state.assessment.counts, severity: state.assessment.severity }
			: null,
		dependencies: state.dependencies
			? { targetFramework: state.dependencies.targetFramework, counts: state.dependencies.counts }
			: null,
		tasks: taskSummary,
	};
	await api.call(session.rpc.extensions, {
		attachments: [{
			type: "extension_context",
			title: `Upgrade Dashboard · ${state.activeScenarioId ?? "no active scenario"}`,
			payload,
		}],
		instanceId: ctx.instanceId,
	});
	return { ok: true, status: "Pushed the current upgrade dashboard context to the chat." };
});

// ---- HTTP server ------------------------------------------------------------

const dashboardServer = createDashboardServer({
	indexHtmlPath: INDEX_HTML_PATH,
	getResolution: async () => ensureResolvedRepo(),
	snapshot,
	getActionHandler: (name) => actionHandlers.get(name) ?? null,
});
const { url: baseUrl } = await dashboardServer.listen();

// ---- Canvas declaration -----------------------------------------------------

const canvas = createCanvas({
	id: "dashboard",
	displayName: "Upgrade Dashboard",
	description:
		"Read-only view of the .NET upgrade artifacts for the current workspace: an Overview landing, plus Activity log, Tasks, Scenario, Projects (table + dependency graph), Dependency health, and Assessment (with incident grouping). Also exposes actions to switch execution mode, share the assessment, and explain dependency issues.",
	actions: [
		{
			name: "refresh",
			description: "Reload artifact state from disk and push it to the canvas.",
			inputSchema: { type: "object", additionalProperties: false },
			handler: (ctx) => actionHandlers.get("refresh")(ctx),
		},
		{
			name: "set_panel",
			description: "Switch the visible panel inside the canvas.",
			inputSchema: {
				type: "object",
				properties: { panel: { type: "string", enum: [...VALID_PANELS] } },
				required: ["panel"],
				additionalProperties: false,
			},
			handler: (ctx) => actionHandlers.get("set_panel")(ctx),
		},
		{
			name: "switch_mode",
			description: "Ask the agent to switch the upgrade execution mode between Guided and Automatic.",
			inputSchema: {
				type: "object",
				properties: { mode: { type: "string", enum: ["guided", "automatic"] } },
				required: ["mode"],
				additionalProperties: false,
			},
			handler: (ctx) => actionHandlers.get("switch_mode")(ctx),
		},
		{
			name: "share_assessment_as_gist",
			description: "Ask the agent to create a private GitHub gist from the current scenario's assessment.json.",
			inputSchema: { type: "object", additionalProperties: false },
			handler: (ctx) => actionHandlers.get("share_assessment_as_gist")(ctx),
		},
		{
			name: "explain_dependency",
			description: "Ask the agent to explain why a NuGet package is flagged in the dependency report and suggest an upgrade path.",
			inputSchema: {
				type: "object",
				properties: { packageName: { type: "string" } },
				required: ["packageName"],
				additionalProperties: false,
			},
			handler: (ctx) => actionHandlers.get("explain_dependency")(ctx),
		},
		{
			name: "push_context",
			description: "Push a structured snapshot of the current upgrade dashboard state (scenario, assessment, dependency, and task summary) into the chat as context for the next message.",
			inputSchema: { type: "object", additionalProperties: false },
			handler: (ctx) => actionHandlers.get("push_context")(ctx),
		},
	],
	async open(ctx) {
		const { instanceId, input } = ctx;
		const resolution = await ensureResolvedRepo(ctx.session?.workingDirectory);
		const initialPanel = VALID_PANELS.has(input?.panel) ? input.panel : "overview";
		const url = `${baseUrl}/?instanceId=${encodeURIComponent(instanceId)}&panel=${encodeURIComponent(initialPanel)}`;

		// ServiceHost is managed by the MCP server (ServiceHostLifecycleService)
		// and runs for the entire MCP server lifetime. The canvas extension is
		// purely UI — it reads activity.jsonl but does not manage the process.

		return { url, title: "Code Upgrade", status: "open" };
	},
	onClose({ instanceId }) {
		dashboardServer.closeInstance(instanceId);
	},
});

session = await joinSession({ canvases: [canvas] });
