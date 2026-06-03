---
name: sge-knowledge-base
description: >
  Use when researching consumer/social app growth tactics, retention loops,
  viral hooks, UGC formats, creator demo patterns, or app-category
  opportunities — especially for wellness, habits, sleep, fitness, mental
  health, and spirituality apps. Queries the Social Growth Engineers article
  corpus and knowledge graph via a shared Convex deployment. Do not
  redistribute raw article text — treat insights as internal research support
  for hypothesis generation, not as quotable source material.
---

# SGE Knowledge Base

A queryable corpus of [Social Growth Engineers](https://www.socialgrowthengineers.com) articles plus a derived knowledge graph. Built and maintained by Bartholomew (the waketask-ios studio's Hermes agent in another deployment) and shared across companies in this Paperclip instance.

The current snapshot: **2,457 articles, 2,477 graph nodes, 27,098 edges** (last regenerated 2026-05-26).

## When to use

Use it when an agent needs evidence-backed answers about:

- Consumer/social mobile app growth tactics (TikTok/IG/Reddit creator playbooks, UGC formats, viral hooks)
- Retention and habit-loop patterns (streaks, identity labels, accountability, lock-screen moments)
- Product ideation in wellness/habits/sleep/mental-health/fitness/spirituality categories
- Creator demo formats (POV, challenge, transformation, comparison, comment-reply, slideshow, duet/remix)
- Date-bounded growth examples (articles carry `publishedAt`; prefer recent evidence)

Do not use it for non-consumer B2B SaaS questions, generic web growth (SEO/PPC), or anything outside the social/mobile growth domain. The corpus is opinionated and that's the point.

## Two query surfaces

### 1. MCP server (recommended)

Wire the MCP server in `scripts/sge-mcp-server.ts` into the agent's MCP config. It exposes four tools:

| Tool | When to use |
| --- | --- |
| `sge_search_graph` | First call when exploring a topic — keyword search across the knowledge graph's nodes (articles, apps, concepts, platforms, metrics, topics). Returns nodes ranked by match score + node centrality weight. |
| `sge_get_neighborhood` | Walk outward from a node found by search. Returns `{ center, nodes[], edges[] }` sorted by edge weight desc. Maps what concepts/apps/articles cluster around a given idea. |
| `sge_list_recent_articles` | "What's new?" — most recently scraped articles, paginated. Use to find anchor articles for graph exploration. |
| `sge_get_graph_stats` | Snapshot the current corpus size + last build timestamp before drawing conclusions. |

Install (one-time, per skill checkout):

```bash
cd skills/sge-knowledge-base/scripts
npm install
```

Wire into an agent's MCP config (example for codex-local / claude-local adapters):

```json
{
  "mcpServers": {
    "sge": {
      "command": "npx",
      "args": ["tsx", "${SKILL_ROOT}/sge-knowledge-base/scripts/sge-mcp-server.ts"],
      "env": {
        "SGE_CONVEX_URL": "https://impressive-rabbit-906.convex.cloud"
      }
    }
  }
}
```

See [references/convex-schema.md](references/convex-schema.md) for the underlying data shape and worked examples.

### 2. Direct Convex HTTP API

If MCP isn't wired, hit Convex directly (no auth — queries are public):

```bash
curl -X POST https://impressive-rabbit-906.convex.cloud/api/query \
  -H 'content-type: application/json' \
  -d '{"path": "knowledgeGraph:searchNodes", "args": {"query": "alarm habit retention", "limit": 10}, "format": "json"}'
```

Available query paths:

- `articles:listRecent` — `{ limit?: number }`
- `knowledgeGraph:stats` — `{}`
- `knowledgeGraph:searchNodes` — `{ graphId?: string, query: string, limit?: number }`
- `knowledgeGraph:neighbors` — `{ graphId?: string, externalId: string, limit?: number }`
- `knowledgeGraph:neighborhood` — `{ graphId?: string, externalId: string, limit?: number }`
- `sources:list` — `{}`

Default `graphId` is `sge-v1`.

## Required environment

| Var | Value | Notes |
| --- | --- | --- |
| `SGE_CONVEX_URL` | `https://impressive-rabbit-906.convex.cloud` | Production deployment. The dev tier (`blissful-oriole-116`) is empty — only the scraper writes to it. |
| `SGE_GRAPH_ID` | `sge-v1` (default) | Override only if the graph is rebuilt under a new id. |

No auth tokens — the read queries are intentionally public. Mutations stay scoped to Bartholomew's scraper container.

## Interpretation guidance

When surfacing results to a user:

1. Cite by `slug` or `url`, never by raw article text — the corpus is internal research support, not for redistribution.
2. Prefer `recencyBucket: last_30d` or `last_90d` hits when the question is about current tactics.
3. Treat recommendations as hypotheses to test, not guarantees.
4. When the question maps to a specific app's domain (e.g. alarms / morning routine / sleep / habit accountability for WakeTask), translate generic patterns into the app's shape: "streak recovery", "lock-screen moments", "creator before/after morning state".

## Known gaps

- **Full-text article search is not yet on Convex.** Bartholomew's local `sge:ask` script reads `storage/sge/articles/` on disk and does in-process search; other agents cannot call this remotely. The knowledge-graph queries above ARE remote and good for concept-level exploration — for full article text today you'd have to route through Bartholomew. Porting the corpus search to a Convex query is on the roadmap.
- **Keyword search only.** No vector embeddings yet. Don't rely on semantic similarity until vector indexes are added.
