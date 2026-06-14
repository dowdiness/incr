const status = document.getElementById('ui-compare-bench-status');
const nativeRequestAnimationFrame = window.requestAnimationFrame?.bind(window);
const nativeCancelAnimationFrame = window.cancelAnimationFrame?.bind(window);

// The benchmark isolates operation + framework flush cost. Rabbita flushes on
// requestAnimationFrame, so the page uses an immediate frame clock for this
// hidden benchmark rather than measuring browser frame scheduling latency.
window.__incrTeaUiCompareNativeRaf = {
  requestAnimationFrame: nativeRequestAnimationFrame,
  cancelAnimationFrame: nativeCancelAnimationFrame,
};
window.requestAnimationFrame = callback => {
  callback(performance.now());
  return 0;
};
window.cancelAnimationFrame = () => {};

await import('../../../_build/js/release/build/examples/incr_tea/browser_bench/browser_bench.js');
await import('../../../_build/js/release/build/examples/incr_tea/browser_ui_compare_bench/browser_ui_compare_bench.js');

if (status) {
  status.textContent = globalThis.__incrTeaUiCompareDomBench?.run
    ? 'ready'
    : 'UI compare bench API failed to install';
}
