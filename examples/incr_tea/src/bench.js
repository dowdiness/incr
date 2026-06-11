import '../../../_build/js/release/build/examples/incr_tea/browser_bench/browser_bench.js';

const status = document.getElementById('bench-status');
if (status) {
  status.textContent = globalThis.__incrTeaDomBench ? 'ready' : 'bench API failed to install';
}
