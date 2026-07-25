# Production operations runbook

This runbook applies to the deployed Worker
`typed-spreadsheet-cloudflare-worker` and its `ROOMS` Durable Object.

## Operating boundary

The service is a transient, two-peer, bearer-capability relay. It has no
accounts, document persistence, presence, reconnect recovery, or per-room
revocation. A capability holder can read and submit opaque protocol frames for
that room. Do not use this service for documents that require identity,
revocation, or confidentiality from Cloudflare.

The stable deployment URL is stored in the protected GitHub environment variable
`CLOUDFLARE_WORKER_URL`. Room admission is also bounded by the Cloudflare Rate
Limit binding at 30 requests per connecting IP per 60 seconds. Credentials are
never copied into this document or passed as command-line arguments.

## Normal release procedure

1. Run the local checks from the Worker package:

   ```bash
   npm ci
   npm run test:hibernation
   npm run test:e2e
   ```

2. Deploy through the protected `cloudflare-worker` GitHub environment. The
   workflow builds the demo and Worker, deploys with Wrangler, and runs the
   production smoke test.

3. For a manual smoke test against an already deployed version:

   ```bash
   SMOKE_BASE_URL="https://<account-subdomain>.workers.dev" npm run smoke:production
   ```

   Replace the placeholder with the deployed Worker URL supplied by the
   operator; do not depend on the GitHub-only environment variable in a local
   shell.

4. Record the Wrangler version ID and smoke result in the release/incident
   record. The smoke test uses random transient room capabilities and does not
   create persistent document data.

## Incident classification

- **P0 security:** capability disclosure, cross-room delivery, unauthorized
  protocol access, or a suspected Worker credential compromise.
- **P1 availability/integrity:** deployed Worker cannot serve the SPA, relay
  messages, enforce the two-peer bound, or enforce frame/rate limits.
- **P2 isolated client issue:** one browser cannot attach or apply a valid
  operation while the Worker smoke test remains green.

When uncertain, treat a capability disclosure or cross-room symptom as P0.

## Detection and evidence

Capture timestamps, deployment version, affected room capability only in the
restricted incident system, and the exact smoke output. Do not paste a live
capability into tickets, chat, or public logs.

Inspect the deployed Worker with Wrangler using an authenticated operator
session:

```bash
npx wrangler tail typed-spreadsheet-cloudflare-worker --format json
npx wrangler versions list
npx wrangler versions view <VERSION_ID>
```

Observability logs are enabled and persisted. Restrict access to the Cloudflare
account because request URLs can contain room capabilities. Do not log protocol
payloads or copy them into incident reports.

## Availability or integrity incident

1. Freeze deploys and record the current version ID.
2. Run the production smoke test to distinguish an edge-wide failure from a
   browser/client issue.
3. If the current version is faulty, select the last known-good version from
   `wrangler versions list` and roll back:

   ```bash
   npx wrangler rollback <KNOWN_GOOD_VERSION_ID>
   ```

4. Run the smoke test again against `CLOUDFLARE_WORKER_URL`.
5. Keep the incident open until `/health`, SPA delivery, relay, duplicate
   forwarding, binary rejection, oversized-frame rejection, and rate limiting
   are green again.

Rollback changes Worker code, not the conceptual room capability contract. Do
not rewrite or remove Durable Object migration history during an incident. The
current Worker does not persist documents, but Durable Object migrations remain
platform state and must be changed only in a planned release.

## Capability disclosure response

A capability is a bearer credential and cannot be individually revoked by the
current no-storage Worker. Origin checks do not contain a leaked capability;
an attacker with the capability can use a non-browser WebSocket client.

For a suspected leaked room:

1. Assume all live opaque frames in that room were exposed.
2. Stop sharing the capability and move participants to a newly generated,
   cryptographically random capability.
3. Close the affected browser sessions and confirm the new room with the
   production smoke path or two trusted clients.
4. Remove the leaked capability from chat, tickets, screenshots, and logs where
   possible. Do not attempt to redact it by editing application logs in place;
   follow the Cloudflare account's retention/access procedure.
5. If many capabilities or the capability-generation process are affected,
   declare P0 and deploy a temporary global room admission block or a new
   capability namespace. This invalidates the no-revocation assumption and
   requires an explicit emergency change.
6. Rotate any Cloudflare API token suspected of exposure through the protected
   GitHub environment, then verify the next deploy and smoke test.

The current design has no per-room kick or revocation endpoint. Adding one is a
security feature redesign, not an operator-side workaround.

## Recovery and closure

Close an incident only after:

- the affected version and capability scope are recorded privately;
- a known-good deployment passes `npm run smoke:production`;
- no new cross-room or boundary-policy failure is observed;
- leaked capabilities, if any, are no longer used;
- a follow-up issue records whether the threat model, retention policy, or
  capability exchange must change.
