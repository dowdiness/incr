import { defineConfig } from 'vite';

const moonbitDemoOutput = /_build\/js\/release\/build\/examples\/typed_spreadsheet_incr_tea_demo\/typed_spreadsheet_incr_tea_demo\.js$/;

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
