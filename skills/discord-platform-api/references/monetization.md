# Monetization

Source: `monetization/implementing-app-subscriptions.md`,
`monetization/implementing-one-time-purchases.md`, `resources/sku.md`,
`resources/entitlement.md`, `resources/subscription.md`.

## Model

Three objects:

| Object | Role |
|---|---|
| SKU | the thing being sold (SKU id, type SUBSCRIPTION or DURATION) |
| Entitlement | a user's/guild's **access right** to a SKU |
| Subscription | the **billing relationship** behind a recurring entitlement |

**Entitlements are the source of truth for access.** Check entitlements, not
subscriptions, when deciding whether to unlock a feature. The Subscription API is for
reporting and lifecycle management outside the interaction flow.

## Entitlement Types

| Type | Value |
|---|---|
| `APPLICATION_SUBSCRIPTION` | 8 |
| `PURCHASE` (one-time) | 9 |
| `PREMIUM_SUBSCRIPTION` | 10 |
| `TEST_MODE` | — (create via API) |

Fields that matter: `id`, `sku_id`, `application_id`, `user_id?`, `guild_id?`,
`type`, `deleted`, `starts_at?`, `ends_at?`, `consumed?`.

`deleted: true` means revoked — filter it out. `ends_at` absent means perpetual.
Test entitlements have **no** `starts_at`/`ends_at`; they live until deleted.

Exactly one of `user_id` / `guild_id` is set.

## Endpoints

```
GET    /applications/{application.id}/entitlements
GET    /applications/{application.id}/entitlements/{entitlement.id}
POST   /applications/{application.id}/entitlements          # create test entitlement
DELETE /applications/{application.id}/entitlements/{entitlement.id}
GET    /applications/{application.id}/skus
GET    /skus/{sku.id}/subscriptions                          # list
GET    /skus/{sku.id}/subscriptions/{subscription.id}        # get
```

Entitlement listing filters: `user_id`, `guild_id`, `sku_ids` (comma separated),
`before`, `after`, `limit` (≤ 100), `exclude_ended`, `exclude_deleted`.

Create test entitlement body:
`{"sku_id": "...", "owner_id": "...", "owner_type": 1|2}` (`1` = guild, `2` = user).

## Gateway Events

`ENTITLEMENT_CREATE`, `ENTITLEMENT_UPDATE`, `ENTITLEMENT_DELETE` arrive on the
gateway. Subscription created/updated/deleted events also exist and are **rare**
(delete especially).

For user-installed apps, entitlement events arrive with the app's own token — do not
assume a guild context.

## One-Time Purchases

Consumables: a `PURCHASE` entitlement is granted, your app **consumes** it
(`POST .../entitlements/{id}/consume`), and the user can buy again. Not consuming
means the user cannot repurchase — this is the classic stuck-purchase bug.

Durable one-time purchases do not need consuming; the entitlement persists.

## Premium Buttons

Button style `6` (`PREMIUM`) with `sku_id` set. Clicking opens Discord's purchase
flow and, on success, delivers `ENTITLEMENT_CREATE` plus an interaction with
`entitlement_sku_ids`. Premium buttons only render if the app has SKUs configured and
the clicker lacks the entitlement; they disappear once owned.

## Premium Required Response

Callback `type: 10` (`PREMIUM_REQUIRED`) is deprecated in favour of letting the
premium button handle purchase. Do not build new flows on it.

## Testing

| Method | Covers | Does not cover |
|---|---|---|
| Test entitlements (`type` test) | subscribed/unsubscribed app behavior | real payment flow |
| Live entitlements (real purchase, then refund/revoke) | full flow incl. Discord UI | requires real money/team setup |

Create a test entitlement for a user or guild, exercise both states, delete it when
done. Test entitlements are valid until deleted.

## Pitfalls

- Checking `Subscription` for access — wrong. Check `Entitlement`.
- Assuming entitlement events always carry a guild — user-installed apps have none.
- Forgetting `consumed` on consumables → user permanently blocked from repurchase.
- Treating `deleted: true` as still active — it is revoked.
- Expecting `starts_at`/`ends_at` on test entitlements — absent by design.
- Granting access from button click alone without waiting for the entitlement event —
  the event is the authoritative grant.
