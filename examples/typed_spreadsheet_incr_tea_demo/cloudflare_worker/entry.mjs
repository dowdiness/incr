// PRODUCTION SKELETON: Cloudflare module/class adapter.
import '../../../_build/js/release/build/examples/typed_spreadsheet_incr_tea_demo/cloudflare_worker/cloudflare_worker.js';

const handlers = globalThis.__typedSpreadsheetCloudflareWorker;

export default {
  fetch(request, env, ctx) {
    return handlers.worker(request, env, ctx);
  },
};

export class TypedSpreadsheetRoomDurableObject {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  fetch(request) {
    return handlers.roomFetch(this.state, request);
  }

  webSocketMessage(socket, message) {
    if (typeof message === 'string') {
      handlers.roomMessage(this.state, socket, message);
    } else {
      socket.close(1003, 'text frames only');
    }
  }

  webSocketClose() {}

  webSocketError() {}
}
