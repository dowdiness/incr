const status = document.getElementById('bench-status');

// The benchmark drives BrowserRenderer::flush_all synchronously. Keep any
// scheduled frame out of the timed loop so it cannot add an unmeasured flush.
window.requestAnimationFrame = () => 0;
window.cancelAnimationFrame = () => {};

await import('../../../_build/js/release/build/examples/incr_tea/browser_bench/browser_bench.js');


if (status) {
  status.textContent = globalThis.__incrTeaControlledReconcileBench?.run
    ? 'ready'
    : 'controlled reconciliation bench API failed to install';
}
