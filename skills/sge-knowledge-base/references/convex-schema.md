# SGE Convex Schema Reference

Snapshot of the queryable tables in the `work-intel` Convex deployment as of the SKILL's `version`. Source of truth: [work-intel/convex/schema.ts](https://github.com/kimprobably/work-intel/blob/main/convex/schema.ts) (private repo; access via Bartholomew).

## Deployment

| Tier | Name | URL | Populated? |
| --- | --- | --- | --- |
| Prod (use this) | `impressive-rabbit-906` | `https://impressive-rabbit-906.convex.cloud` | Yes — 2,457 articles, 2,477 nodes, 27,098 edges as of 2026-05-26 |
| Dev | `blissful-oriole-116` | `https://blissful-oriole-116.convex.cloud` | No — empty / scraper-target only |

The `.env.local` inside `work-intel` points at the dev deployment because that's where the scraper writes during local development. Other agents should query **prod**.

## Tables and what's worth querying

### `articles`

One row per scraped article. Indexed by URL. Mutations (`upsertParsed`) are scraper-internal; agents read via the query exports.

Key fields:

| Field | Type | Notes |
| --- | --- | --- |
| `url` | string | Article URL (also indexed). |
| `slug` | string | Stable identifier for cross-references. |
| `title` | string | Article title. |
| `publishedAt` | string? | ISO date. Prefer this when reasoning about recency. |
| `recencyBucket` | enum | `last_30d \| last_90d \| last_180d \| last_365d \| older \| unknown`. |
| `categoryLabels` | string[] | Topic tags. |
| `domainLabels` | string[] | Vertical tags (e.g. `wellness`, `habits`). |
| `isRelevantToWakeTask` | bool | Set by the relevance scorer. |
| `summary` | string? | AI-summarized article. |
| `keyTakeaways` | string[] | Bullet-form takeaways. |
| `cleanText` | string? | Full parsed text (large; agents usually want `summary` + takeaways instead). |

Public queries:

- `articles:listRecent({ limit?: number })` → `Article[]` ordered desc by `_creationTime`.

### `graphNodes`

Knowledge-graph entities derived from the corpus.

| Field | Type | Notes |
| --- | --- | --- |
| `graphId` | string | Default `sge-v1`. |
| `externalId` | string | Stable id within the graph. Pass to `neighbors` / `neighborhood`. |
| `type` | enum | `article \| app \| concept \| platform \| metric \| topic`. |
| `label` | string | Display name. |
| `weight` | number | Centrality / importance score. |
| `url` | string? | When the node is an article or external entity. |
| `slug` | string? | When applicable. |
| `community` | string? | Cluster label from graph partitioning. |

### `graphEdges`

Typed relationships between nodes. `type` ∈ `mentions | shared_concept | related_post | same_topic_recent | title_similarity`. Weights are normalized 0..1 with higher = stronger relationship.

### `graphMeta`

Singleton per `graphId` with build stats (`articles`, `nodes`, `edges`, `concepts`, `apps`, `generatedAt`). Hit via `knowledgeGraph:stats` to know what you're querying.

### `sources`

Upstream content sources. Currently just SGE. Query via `sources:list`.

## Worked query examples

### Find concepts related to "alarm habit retention"

```bash
curl -X POST https://impressive-rabbit-906.convex.cloud/api/query \
  -H 'content-type: application/json' \
  -d '{"path":"knowledgeGraph:searchNodes","args":{"query":"alarm habit retention","limit":10}}'
```

Returns `GraphNode[]` with a synthetic `score` field. Pick the top hit's `externalId` to walk outward:

### Walk the neighborhood of a node

```bash
curl -X POST https://impressive-rabbit-906.convex.cloud/api/query \
  -H 'content-type: application/json' \
  -d '{"path":"knowledgeGraph:neighborhood","args":{"externalId":"concept:streak-recovery","limit":25}}'
```

Returns `{ center, nodes[], edges[] }` — the neighbor set with edges sorted by weight desc.

### List most recent articles

```bash
curl -X POST https://impressive-rabbit-906.convex.cloud/api/query \
  -H 'content-type: application/json' \
  -d '{"path":"articles:listRecent","args":{"limit":15}}'
```

## Auth model

All exported queries are public — no auth header required. Mutations are not exposed to agents; they're invoked only by `work-intel`'s scraper scripts running under Bartholomew's environment.

If we ever need to gate read access (e.g., for sensitive verticals), the move is to add `ctx.auth.getUserIdentity()` checks inside the query handlers and require agents to send a Convex auth JWT. Not needed today.
