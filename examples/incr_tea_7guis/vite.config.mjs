import { defineConfig } from 'vite';

const moonbitDemoOutput = /_build\/js\/release\/build\/examples\/incr_tea_7guis\/incr_tea_7guis\.js$/;

function serveMoonBitOutputVerbatim() {
  return {
    name: 'serve-moonbit-output-verbatim',
    apply: 'serve',
    enforce: 'pre',
    transform(code, id) {
      const [path] = id.split('?');
      if (!moonbitDemoOutput.test(path)) return null;
      return { code, map: null };
    },
  };
}

export default defineConfig({
  plugins: [serveMoonBitOutputVerbatim()],
  server: {
    fs: {
      allow: ['../..'],
    },
  },
  build: {
    target: 'esnext',
  },
});
