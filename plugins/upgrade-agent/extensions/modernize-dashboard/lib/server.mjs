// Copyright (c) Microsoft Corporation. All rights reserved.

// Loopback HTTP/SSE server. Serves the iframe HTML, exposes /api/state and
// /events for the canvas UI, and dispatches POST /action to caller-provided
// handlers. Used by both the canvas extension (extension.mjs) and the
// standalone CLI (bin/cli.mjs).

import http from "node:http";
import { promises as fs } from "node:fs";

import { hashState } from "./state-hash.mjs";

// Create and start a dashboard server on `port` (0 = random). Returns a
// handle with { server, port, url, broadcastAll, close }.
//
// Options:
//   port:           number — listen port (default 0 for random)
//   host:           string — bind address (default "127.0.0.1"; loopback only)
//   indexHtmlPath:  string — absolute path to the iframe HTML
//   getResolution(instanceId): { path, source } | null | Promise<...>
//     Resolves to the repo root + a human-readable source. Called per request.
//   snapshot(repoRoot, resolution): Promise<state>
//     Returns the current dashboard state snapshot.
//   getActionHandler(actionName): handler | null
//     Returns the handler for an action name. The handler is called with the
//     same shape canvas action handlers receive: { sessionId, extensionId,
//     canvasId, instanceId, actionName, input } → result.
//   pollIntervalMs: number — how often to re-snapshot and SSE-broadcast (default 5000)
export function createDashboardServer(options) {
	const {
		port = 0,
		host = "127.0.0.1",
		indexHtmlPath,
		getResolution,
		snapshot,
		getActionHandler,
		pollIntervalMs = 5000,
	} = options;

	if (!indexHtmlPath) throw new Error("createDashboardServer: indexHtmlPath is required");
	if (typeof getResolution !== "function") throw new Error("createDashboardServer: getResolution is required");
	if (typeof snapshot !== "function") throw new Error("createDashboardServer: snapshot is required");
	if (typeof getActionHandler !== "function") throw new Error("createDashboardServer: getActionHandler is required");

	// instanceId -> { resolution, lastStateHash }
	const instanceMeta = new Map();
	// instanceId -> Set<ServerResponse> (SSE subscribers scoped to this instance)
	const instanceSubscribers = new Map();

	function getInstanceMeta(instanceId) {
		let meta = instanceMeta.get(instanceId);
		if (!meta) {
			meta = { resolution: null, lastStateHash: null };
			instanceMeta.set(instanceId, meta);
		}
		return meta;
	}

	function getInstanceSubscribers(instanceId) {
		let subs = instanceSubscribers.get(instanceId);
		if (!subs) {
			subs = new Set();
			instanceSubscribers.set(instanceId, subs);
		}
		return subs;
	}

	async function broadcastToInstance(instanceId, { force = false } = {}) {
		const subs = instanceSubscribers.get(instanceId);
		if (!subs || subs.size === 0) return;
		const meta = getInstanceMeta(instanceId);
		const resolution = meta.resolution ?? (await getResolution(instanceId));
		if (!resolution) return;
		meta.resolution = resolution;
		const state = await snapshot(resolution.path, resolution);
		const hash = hashState(state);
		if (!force && hash === meta.lastStateHash) return;
		meta.lastStateHash = hash;
		const payload = `data: ${JSON.stringify(state)}\n\n`;
		for (const res of subs) {
			try {
				res.write(payload);
			} catch {
				// ignore
			}
		}
	}

	async function broadcastAll({ force = false } = {}) {
		for (const instanceId of instanceSubscribers.keys()) {
			try {
				await broadcastToInstance(instanceId, { force });
			} catch {
				// ignore
			}
		}
	}

	// Tear down all per-instance state when a canvas instance is closed: end any
	// lingering SSE responses, drop the subscriber set + cached snapshot meta,
	// and stop the poll timer once no instances remain.
	function closeInstance(instanceId) {
		const subs = instanceSubscribers.get(instanceId);
		if (subs) {
			for (const res of subs) {
				try { res.end(); } catch { /* ignore */ }
			}
			instanceSubscribers.delete(instanceId);
		}
		instanceMeta.delete(instanceId);
		if (instanceSubscribers.size === 0) stopPolling();
	}

	let pollTimer = null;
	function startPollingIfNeeded() {
		if (pollTimer) return;
		pollTimer = setInterval(() => {
			broadcastAll().catch(() => {});
		}, pollIntervalMs);
	}

	function stopPolling() {
		if (pollTimer) {
			clearInterval(pollTimer);
			pollTimer = null;
		}
	}

	async function handleRequest(req, res) {
		const url = new URL(req.url ?? "/", `http://${host}`);
		const instanceId = url.searchParams.get("instanceId") ?? "default";

		if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
			const html = await fs.readFile(indexHtmlPath);
			res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
			res.end(html);
			return;
		}

		if (req.method === "GET" && url.pathname === "/api/state") {
			const meta = getInstanceMeta(instanceId);
			const resolution = meta.resolution ?? (await getResolution(instanceId));
			if (!resolution) {
				res.writeHead(503);
				res.end("repo not resolved");
				return;
			}
			meta.resolution = resolution;
			const state = await snapshot(resolution.path, resolution);
			meta.lastStateHash = hashState(state);
			res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
			res.end(JSON.stringify(state));
			return;
		}

		if (req.method === "GET" && url.pathname === "/events") {
			res.writeHead(200, {
				"content-type": "text/event-stream",
				"cache-control": "no-cache",
				connection: "keep-alive",
			});
			res.write(": connected\n\n");
			const subs = getInstanceSubscribers(instanceId);
			subs.add(res);
			// SSE keepalive: write a comment heartbeat every 20s. Without this
			// idle proxies/host bridges may close the connection, surfacing as a
			// "disconnected — retrying" toast in the canvas after a few minutes
			// of inactivity even when nothing has gone wrong.
			const keepalive = setInterval(() => {
				try {
					res.write(": ping\n\n");
				} catch {
					// ignore
				}
			}, 20000);
			// Clean up on either the client disconnecting ("close" on the
			// request) or the server ending the response ("close" on the
			// response, e.g. via closeInstance). A server-side res.end() does
			// not reliably fire the request's "close", so listen on both;
			// clearInterval + subs.delete are idempotent.
			const cleanup = () => {
				clearInterval(keepalive);
				subs.delete(res);
			};
			req.on("close", cleanup);
			res.on("close", cleanup);
			const meta = getInstanceMeta(instanceId);
			const resolution = meta.resolution ?? (await getResolution(instanceId));
			if (resolution) {
				meta.resolution = resolution;
				const state = await snapshot(resolution.path, resolution);
				meta.lastStateHash = hashState(state);
				try {
					res.write(`data: ${JSON.stringify(state)}\n\n`);
				} catch {
					// ignore
				}
			}
			startPollingIfNeeded();
			return;
		}

		if (req.method === "POST" && url.pathname === "/action") {
			let body = "";
			req.on("data", (chunk) => { body += chunk; });
			req.on("end", async () => {
				try {
					const payload = JSON.parse(body || "{}");
					const actionName = typeof payload.actionName === "string" ? payload.actionName : "";
					const handler = getActionHandler(actionName);
					if (!handler) {
						res.writeHead(404, { "content-type": "application/json" });
						res.end(JSON.stringify({ error: `Unknown action: ${actionName}` }));
						return;
					}
					const ctx = {
						sessionId: "",
						extensionId: "",
						canvasId: "dashboard",
						instanceId: typeof payload.instanceId === "string" ? payload.instanceId : instanceId,
						actionName,
						input: payload.input,
						broadcastToInstance,
					};
					const result = await handler(ctx);
					const meta = getInstanceMeta(ctx.instanceId);
					const resolution = meta.resolution ?? (await getResolution(ctx.instanceId));
					if (resolution) {
						meta.resolution = resolution;
						const state = await snapshot(resolution.path, resolution);
						meta.lastStateHash = hashState(state);
						res.writeHead(200, { "content-type": "application/json" });
						res.end(JSON.stringify({ result, state }));
					} else {
						res.writeHead(200, { "content-type": "application/json" });
						res.end(JSON.stringify({ result, state: null }));
					}
				} catch (err) {
					res.writeHead(400, { "content-type": "application/json" });
					res.end(JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }));
				}
			});
			return;
		}

		res.writeHead(404);
		res.end("not found");
	}

	const server = http.createServer((req, res) => {
		handleRequest(req, res).catch((err) => {
			try {
				res.writeHead(500);
				res.end(err?.message ?? "internal error");
			} catch {
				// ignore
			}
		});
	});

	return {
		server,
		broadcastAll,
		broadcastToInstance,
		closeInstance,
		stopPolling,
		async listen() {
			await new Promise((resolve) => server.listen(port, host, resolve));
			const addr = server.address();
			const resolvedPort = typeof addr === "object" && addr ? addr.port : port;
			return {
				port: resolvedPort,
				url: `http://${host}:${resolvedPort}`,
			};
		},
		async close() {
			stopPolling();
			for (const subs of instanceSubscribers.values()) {
				for (const res of subs) {
					try { res.end(); } catch { /* ignore */ }
				}
			}
			instanceSubscribers.clear();
			instanceMeta.clear();
			await new Promise((resolve) => server.close(() => resolve()));
		},
	};
}
