# Typed spreadsheet Cloudflare Worker

Production implementation skeleton for Issue #425.

This phase verifies the Worker → Durable Object boundary, static SPA assets,
and a two-connection opaque text relay. The Worker routes `/health`,
`/api/rooms/<capability>`, `/`, and `/collab`; the Durable Object accepts
Hibernation WebSockets, excludes the sender, limits the room to two connections,
and rejects oversized text frames. The Worker also validates canonical URL-safe
room capabilities and same-site origins. Spreadsheet protocol and rate limits
are implemented in later phases.

## Run locally

```bash
npm install
npm run dev
```

The generated MoonBit module is loaded by `entry.mjs`. Cloudflare's Worker and
Durable Object exports remain the only JavaScript adapter surface.
