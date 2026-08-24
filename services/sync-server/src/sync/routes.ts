import { Router } from "express";
import { z } from "zod";
import { config } from "../config";
import { requireAuth } from "../auth/middleware";
import { applyPush, pullDelta } from "./store";

export const syncRouter = Router();
syncRouter.use(requireAuth);

const pushItemSchema = z.object({
  kind: z.string().trim().min(1).max(64),
  key: z.string().trim().min(1).max(512),
  payload: z.unknown().optional(),
  updatedAt: z.number().int().nonnegative(),
  deleted: z.boolean().optional().default(false),
});

const pushSchema = z.object({
  items: z.array(pushItemSchema).min(1).max(config.maxSyncItemsPerPush),
});

syncRouter.post("/push", (req, res) => {
  const parsed = pushSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid push payload", details: parsed.error.flatten() });
    return;
  }

  const results = applyPush(req.auth!.userId, parsed.data.items);
  res.json({ results });
});

const pullQuerySchema = z.object({
  since: z.coerce.number().int().nonnegative().optional().default(0),
  limit: z.coerce.number().int().positive().max(2000).optional().default(1000),
});

syncRouter.get("/pull", (req, res) => {
  const parsed = pullQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid query", details: parsed.error.flatten() });
    return;
  }

  const { since, limit } = parsed.data;
  const rows = pullDelta(req.auth!.userId, since, limit);
  const items = rows.map((row) => ({
    kind: row.kind,
    key: row.item_key,
    payload: JSON.parse(row.payload),
    updatedAt: row.updated_at,
    deleted: row.deleted === 1,
  }));
  const cursor = rows.length > 0 ? rows[rows.length - 1].seq : since;

  res.json({ items, cursor, hasMore: rows.length === limit });
});
