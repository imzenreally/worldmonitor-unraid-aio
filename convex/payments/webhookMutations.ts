import {
  internalMutation,
  internalQuery,
  type MutationCtx,
  type QueryCtx,
} from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import { v } from "convex/values";
import {
  handleSubscriptionActive,
  handleSubscriptionRenewed,
  handleSubscriptionOnHold,
  handleSubscriptionCancelled,
  handleSubscriptionPlanChanged,
  handleSubscriptionExpired,
  handleSubscriptionUpdated,
  handlePaymentOrRefundEvent,
  handleDisputeEvent,
} from "./subscriptionHelpers";

const MAX_FAILURE_MESSAGE_LENGTH = 1000;
const MAX_FAILURE_DATA_KEYS = 100;
const MAX_DIAGNOSTIC_ROWS = 250;
type EventTypeCount = { eventType: string; count: number };

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function boundedString(value: unknown, maxLength: number): string | undefined {
  return typeof value === "string" && value.length > 0
    ? value.slice(0, maxLength)
    : undefined;
}

/** Keep failure rows useful to operators without copying payload values. */
function sanitizeFailureMessage(value: string): string {
  return value
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, "[redacted-email]")
    .replace(/\b(bearer|token|secret|api[_-]?key|password)\s*[:=]\s*\S+/gi, "$1=[redacted]")
    .slice(0, MAX_FAILURE_MESSAGE_LENGTH);
}

function extractFailureContext(rawPayload: unknown) {
  const payload = asRecord(rawPayload);
  const data = asRecord(payload?.data);
  const customer = asRecord(data?.customer);

  return {
    dodoSubscriptionId: boundedString(data?.subscription_id, 200),
    dodoPaymentId: boundedString(data?.payment_id, 200),
    dodoCustomerId: boundedString(customer?.customer_id, 200),
    dataKeys: data
      ? Object.keys(data).sort().slice(0, MAX_FAILURE_DATA_KEYS)
      : [],
  };
}

function adjustEventTypeCount(
  counts: EventTypeCount[],
  eventType: string,
  delta: number,
): EventTypeCount[] {
  const next = counts.map((entry) => ({ ...entry }));
  const entry = next.find((candidate) => candidate.eventType === eventType);
  if (entry) {
    entry.count += delta;
  } else if (delta > 0) {
    next.push({ eventType, count: delta });
  }
  return next
    .filter((candidate) => candidate.count > 0)
    .sort((a, b) => a.eventType.localeCompare(b.eventType));
}

async function updateFailureSummary(
  ctx: MutationCtx,
  existing: Doc<"paymentWebhookFailures"> | null,
  eventType: string,
  updatedAt: number,
) {
  const summary = await ctx.db
    .query("paymentWebhookFailureSummary")
    .withIndex("by_key", (q) => q.eq("key", "global"))
    .unique();

  if (!summary) {
    await ctx.db.insert("paymentWebhookFailureSummary", {
      key: "global",
      unresolvedCount: 1,
      eventTypes: [{ eventType, count: 1 }],
      updatedAt,
    });
    return;
  }

  let unresolvedCount = summary.unresolvedCount;
  let eventTypes = summary.eventTypes;
  if (existing?.unresolved) {
    // A repeated failure normally keeps the same event type. Handle a
    // provider correction defensively so the aggregate remains truthful.
    if (existing.eventType !== eventType) {
      eventTypes = adjustEventTypeCount(eventTypes, existing.eventType, -1);
      eventTypes = adjustEventTypeCount(eventTypes, eventType, 1);
    }
  } else {
    unresolvedCount += 1;
    eventTypes = adjustEventTypeCount(eventTypes, eventType, 1);
  }

  await ctx.db.patch(summary._id, {
    unresolvedCount,
    eventTypes,
    updatedAt,
  });
}

async function getUnresolvedFailureSummary(ctx: QueryCtx) {
  const rows = await ctx.db
    .query("paymentWebhookFailureSummary")
    .withIndex("by_key", (q) => q.eq("key", "global"))
    .unique();
  return {
    unresolvedCount: rows?.unresolvedCount ?? 0,
    eventTypes: rows?.eventTypes.map((entry) => entry.eventType) ?? [],
  };
}

export const recordWebhookFailure = internalMutation({
  args: {
    webhookId: v.string(),
    eventType: v.string(),
    rawPayload: v.any(),
    timestamp: v.number(),
    receivedAt: v.optional(v.number()),
    errorKind: v.string(),
    errorMessage: v.string(),
  },
  handler: async (ctx, args) => {
    const receivedAt = args.receivedAt ?? Date.now();
    const context = extractFailureContext(args.rawPayload);
    const existing = await ctx.db
      .query("paymentWebhookFailures")
      .withIndex("by_webhookId", (q) => q.eq("webhookId", args.webhookId))
      .first();

    const attemptCount = (existing?.attemptCount ?? 0) + 1;
    const failure = {
      webhookId: args.webhookId,
      eventType: args.eventType,
      ...context,
      errorKind: sanitizeFailureMessage(args.errorKind),
      errorMessage: sanitizeFailureMessage(args.errorMessage),
      eventTimestamp: args.timestamp,
      lastSeenAt: receivedAt,
      attemptCount,
      unresolved: true,
      // A retry after manual resolution is a fresh unresolved incident, so
      // clear the old resolution marker while retaining receivedAt/history.
      resolvedAt: undefined,
      resolvedBy: undefined,
      resolutionNote: undefined,
    };

    if (existing) {
      await ctx.db.patch(existing._id, failure);
    } else {
      await ctx.db.insert("paymentWebhookFailures", {
        ...failure,
        receivedAt,
      });
    }

    await updateFailureSummary(ctx, existing, args.eventType, receivedAt);
    const summary = await getUnresolvedFailureSummary(ctx);
    return {
      isNew: !existing,
      attemptCount,
      errorKind: failure.errorKind,
      errorMessage: failure.errorMessage,
      ...summary,
    };
  },
});

/**
 * Emits one grouped Convex auto-Sentry event after a failure row commits.
 * Convex forwards structured console errors to Sentry; using a non-throwing
 * mutation keeps the provider retry path and scheduled-function bookkeeping
 * independent of the ops signal.
 */
export const reportDodoWebhookFailure = internalMutation({
  args: {
    webhookId: v.string(),
    eventType: v.string(),
    errorKind: v.string(),
    errorMessage: v.string(),
    attemptCount: v.number(),
    unresolvedCount: v.number(),
    eventTypes: v.array(v.string()),
  },
  handler: async (_ctx, args) => {
    // sentry-coverage-ok: Convex auto-Sentry forwards this structured ops
    // signal. It is intentionally non-throwing so the scheduler does not
    // retry or create an unhandled test/deployment failure.
    console.error(
      `[webhook] Dodo processing failure (webhookId=${args.webhookId}, eventType=${args.eventType}, errorKind=${args.errorKind}, attemptCount=${args.attemptCount}, unresolvedCount=${args.unresolvedCount}, affectedEventTypes=${args.eventTypes.join(",")}): ${sanitizeFailureMessage(args.errorMessage)}`,
    );
  },
});

export const resolveWebhookFailure = internalMutation({
  args: {
    webhookId: v.string(),
    resolvedBy: v.string(),
    resolutionNote: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("paymentWebhookFailures")
      .withIndex("by_webhookId", (q) => q.eq("webhookId", args.webhookId))
      .first();
    if (!existing) {
      throw new Error(`No Dodo webhook failure found for ${args.webhookId}`);
    }

    await ctx.db.patch(existing._id, {
      unresolved: false,
      resolvedAt: Date.now(),
      resolvedBy: args.resolvedBy.slice(0, 200),
      resolutionNote: args.resolutionNote
        ? sanitizeFailureMessage(args.resolutionNote)
        : undefined,
    });

    if (existing.unresolved) {
      const summary = await ctx.db
        .query("paymentWebhookFailureSummary")
        .withIndex("by_key", (q) => q.eq("key", "global"))
        .unique();
      if (summary) {
        await ctx.db.patch(summary._id, {
          unresolvedCount: Math.max(0, summary.unresolvedCount - 1),
          eventTypes: adjustEventTypeCount(summary.eventTypes, existing.eventType, -1),
          updatedAt: Date.now(),
        });
      }
    }
  },
});

export const listUnresolvedWebhookFailures = internalQuery({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = Math.max(
      1,
      Math.min(args.limit ?? 100, MAX_DIAGNOSTIC_ROWS),
    );
    return await ctx.db
      .query("paymentWebhookFailures")
      .withIndex("by_unresolved_lastSeenAt", (q) => q.eq("unresolved", true))
      .order("desc")
      .take(limit);
  },
});

/**
 * Idempotent webhook event processor.
 *
 * Receives parsed webhook data from the HTTP action handler,
 * deduplicates by webhook-id, records the event, and dispatches
 * to event-type-specific handlers from subscriptionHelpers.
 *
 * On handler failure, the error is thrown so Convex rolls back the
 * transaction. The HTTP handler records a sanitized failure projection in a
 * separate mutation before returning 500, which triggers Dodo's retry.
 */
export const processWebhookEvent = internalMutation({
  args: {
    webhookId: v.string(),
    eventType: v.string(),
    rawPayload: v.any(),
    timestamp: v.number(),
  },
  handler: async (ctx, args) => {
    // 1. Idempotency check: skip only if already successfully processed.
    //    Failed events are deleted so the retry can re-process cleanly.
    const existing = await ctx.db
      .query("webhookEvents")
      .withIndex("by_webhookId", (q) => q.eq("webhookId", args.webhookId))
      .first();

    if (existing) {
      // Records are only inserted after successful processing (see step 3 below).
      // If the handler throws, Convex rolls back the transaction and no record
      // is written. So `existing` always has status "processed" — it's a true
      // duplicate we can safely skip.
      console.warn(`[webhook] Duplicate webhook ${args.webhookId}, already processed — skipping`);
      return;
    }

    // 2. Dispatch to event-type-specific handlers.
    //    Errors propagate (throw) so Convex rolls back the entire transaction,
    //    preventing partial writes (e.g., subscription without entitlements).
    //    The HTTP handler catches thrown errors and returns 500 to trigger retries.
    const data = args.rawPayload.data;

    // Minimum shape guard — throw so Convex rolls back and returns 500,
    // causing Dodo to retry instead of silently dropping the event.
    // The HTTP action records a durable dead-letter projection after this
    // mutation rejects, outside this transaction, so permanent schema
    // mismatches remain repairable after Dodo exhausts its retries.
    if (!data || typeof data !== 'object') {
      throw new Error(
        `[webhook] rawPayload.data is missing or not an object (eventType=${args.eventType}, webhookId=${args.webhookId})`,
      );
    }

    const subscriptionEvents = [
      "subscription.active", "subscription.renewed", "subscription.on_hold",
      "subscription.cancelled", "subscription.plan_changed", "subscription.expired",
      // PR 3 (post-launch-stabilization): Dodo's docs list `subscription.updated`
      // as a real-time-sync event for any subscription field change. Handler
      // dispatches by the payload's `status` field to reuse our existing
      // lifecycle logic AND respect the paid-through-cancellation policy.
      "subscription.updated",
    ] as const;

    if (subscriptionEvents.includes(args.eventType as typeof subscriptionEvents[number]) && !(data as Record<string, unknown>).subscription_id) {
      throw new Error(
        `[webhook] Missing subscription_id for subscription event (eventType=${args.eventType}, webhookId=${args.webhookId}, dataKeys=${Object.keys(data as object).join(",")})`,
      );
    }

    switch (args.eventType) {
      case "subscription.active":
        await handleSubscriptionActive(ctx, data, args.timestamp);
        break;
      case "subscription.renewed":
        await handleSubscriptionRenewed(ctx, data, args.timestamp);
        break;
      case "subscription.on_hold":
        await handleSubscriptionOnHold(ctx, data, args.timestamp);
        break;
      case "subscription.cancelled":
        await handleSubscriptionCancelled(ctx, data, args.timestamp);
        break;
      case "subscription.plan_changed":
        await handleSubscriptionPlanChanged(ctx, data, args.timestamp);
        break;
      case "subscription.expired":
        await handleSubscriptionExpired(ctx, data, args.timestamp);
        break;
      case "subscription.updated":
        await handleSubscriptionUpdated(ctx, data, args.timestamp);
        break;
      case "payment.succeeded":
      case "payment.failed":
      // `payment.processing` is Dodo's only non-terminal payment event; its
      // payload `data.status` carries the 3DS/SCA-pending `requires_customer_action`
      // state. `payment.cancelled` is terminal-but-uncharged. Persisting these
      // gives the app a pending-payment signal for duplicate-prevention (#4438)
      // and reconciliation (#4439); previously they fell through to `default`
      // and were dropped while the payment sat in "Requires customer action" on
      // Dodo's dashboard. (`payment.requires_customer_action` is NOT a Dodo event
      // type — see derivePaymentEventStatus in subscriptionHelpers.ts.)
      case "payment.processing":
      case "payment.cancelled":
      case "refund.succeeded":
      case "refund.failed":
        await handlePaymentOrRefundEvent(ctx, data, args.eventType, args.timestamp);
        break;
      case "dispute.opened":
      case "dispute.won":
      case "dispute.lost":
      case "dispute.closed":
        await handleDisputeEvent(ctx, data, args.eventType, args.timestamp);
        break;
      default:
        // Loud signal for `subscription.*` additions (so a future Dodo event
        // type doesn't silently no-op). Other unhandled events remain a warn.
        if (typeof args.eventType === "string" && args.eventType.startsWith("subscription.")) {
          console.error(
            `[webhook] Unhandled subscription.* event type: ${args.eventType} — needs a dedicated handler in subscriptionHelpers.ts`,
          );
        } else {
          console.warn(`[webhook] Unhandled event type: ${args.eventType}`);
        }
    }

    // 3. Record the event AFTER successful processing.
    //    If the handler threw, we never reach here — the transaction rolls back
    //    and Dodo retries. Only successful events are recorded for idempotency.
    await ctx.db.insert("webhookEvents", {
      webhookId: args.webhookId,
      eventType: args.eventType,
      rawPayload: args.rawPayload,
      processedAt: Date.now(),
      status: "processed",
    });
  },
});
