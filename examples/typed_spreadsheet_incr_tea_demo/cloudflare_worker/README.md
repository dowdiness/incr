# Typed spreadsheet Cloudflare Worker

Production implementation skeleton for Issue #425.

This phase verifies only the Worker → Durable Object boundary. The Worker
routes `/health` and `/api/rooms/<room>`; the Durable Object currently returns a
status response. Spreadsheet protocol, WebSocket relay, room capabilities,
limits, static assets, and browser transport are implemented in later phases.

## Run locally

```bash
npm install
npm run dev
```

The generated MoonBit module is loaded by `entry.mjs`. Cloudflare's Worker and
Durable Object exports remain the only JavaScript adapter surface.
