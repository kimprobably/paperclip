#!/usr/bin/env node
/**
 * SGE MCP Server.
 *
 * Wraps the work-intel Convex deployment's public read queries as MCP tools so
 * any MCP-capable agent (Claude Code, Codex, Cursor, Paperclip-hired agents,
 * Bartholomew via Hermes) can query the Social Growth Engineers corpus and
 * knowledge graph without knowing Convex.
 *
 * Stdio transport. Single file. Zero stateful client — every call goes through
 * Convex HTTP.
 *
 * Env:
 *   SGE_CONVEX_URL   Required. Default: https://blissful-oriole-116.convex.cloud
 *   SGE_GRAPH_ID     Optional. Default: sge-v1
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const CONVEX_URL = (process.env.SGE_CONVEX_URL ?? "https://impressive-rabbit-906.convex.cloud").replace(/\/$/, "");
const DEFAULT_GRAPH_ID = process.env.SGE_GRAPH_ID ?? "sge-v1";

async function convexQuery(path: string, args: Record<string, unknown>): Promise<unknown> {
  const res = await fetch(`${CONVEX_URL}/api/query`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ path, args, format: "json" }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(`convex ${path} → ${res.status}: ${text.slice(0, 500)}`);
  }
  const payload = (await res.json()) as { status: string; value?: unknown; errorMessage?: string };
  if (payload.status !== "success") {
    throw new Error(`convex ${path} returned ${payload.status}: ${payload.errorMessage ?? "unknown"}`);
  }
  return payload.value;
}

const server = new Server(
  { name: "sge-knowledge-base", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

const TOOLS = [
  {
    name: "sge_search_graph",
    description:
      "Keyword search across the Social Growth Engineers knowledge graph. Returns nodes (articles, apps, concepts, platforms, metrics, topics) ranked by match score + node centrality weight. Use this first when exploring a topic; then walk outward with sge_get_neighborhood.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Free-text search. Tokenized on word boundaries (≥2 chars per token)." },
        limit: { type: "number", description: "Max nodes to return. Default 20.", default: 20 },
        graphId: { type: "string", description: "Override the graph id. Default sge-v1." },
      },
      required: ["query"],
    },
  },
  {
    name: "sge_get_neighborhood",
    description:
      "Pull a node's neighbors (incoming + outgoing edges) with edge weights. Use to map what concepts/apps/articles cluster around a given externalId. Returns { center, nodes[], edges[] } with edges sorted by weight desc.",
    inputSchema: {
      type: "object",
      properties: {
        externalId: { type: "string", description: "Node's externalId, obtained from sge_search_graph." },
        limit: { type: "number", description: "Max edges (and consequently nodes) to return. Default 50.", default: 50 },
        graphId: { type: "string", description: "Override the graph id. Default sge-v1." },
      },
      required: ["externalId"],
    },
  },
  {
    name: "sge_list_recent_articles",
    description:
      "Most recently scraped SGE articles, ordered by creation time desc. Use when the question is 'what's new' or to find anchor articles for further graph exploration. Returns articles with summary, keyTakeaways, categoryLabels, recencyBucket.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number", description: "Max articles to return. Default 15, max 50.", default: 15 },
      },
    },
  },
  {
    name: "sge_get_graph_stats",
    description:
      "Snapshot of the current graph: counts of articles, nodes, edges, concepts, apps, and the last generation timestamp. Use to know what you're querying before drawing conclusions.",
    inputSchema: {
      type: "object",
      properties: {
        graphId: { type: "string", description: "Override the graph id. Default sge-v1." },
      },
    },
  },
] as const;

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: rawArgs } = req.params;
  const args = (rawArgs ?? {}) as Record<string, unknown>;
  const graphId = (args.graphId as string | undefined) ?? DEFAULT_GRAPH_ID;

  try {
    let value: unknown;
    switch (name) {
      case "sge_search_graph":
        value = await convexQuery("knowledgeGraph:searchNodes", {
          query: String(args.query ?? ""),
          limit: typeof args.limit === "number" ? args.limit : 20,
          graphId,
        });
        break;
      case "sge_get_neighborhood":
        value = await convexQuery("knowledgeGraph:neighborhood", {
          externalId: String(args.externalId ?? ""),
          limit: typeof args.limit === "number" ? args.limit : 50,
          graphId,
        });
        break;
      case "sge_list_recent_articles":
        value = await convexQuery("articles:listRecent", {
          limit: typeof args.limit === "number" ? Math.min(args.limit, 50) : 15,
        });
        break;
      case "sge_get_graph_stats":
        value = await convexQuery("knowledgeGraph:stats", { graphId });
        break;
      default:
        throw new Error(`unknown tool: ${name}`);
    }
    return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      isError: true,
      content: [{ type: "text", text: `error: ${message}` }],
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
// MCP servers run until stdin closes; no manual loop needed.
