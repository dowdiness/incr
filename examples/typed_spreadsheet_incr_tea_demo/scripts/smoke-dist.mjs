import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const distRoot = resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const host = '127.0.0.1';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

function filePathForRequest(pathname) {
  const localPath = pathname === '/' ? '/index.html' : decodeURIComponent(pathname);
  const filePath = resolve(distRoot, `.${localPath}`);
  assert(
    filePath === distRoot || filePath.startsWith(`${distRoot}${sep}`),
    `Refusing to serve path outside dist: ${pathname}`,
  );
  return filePath;
}

function localAssetUrls(html, tagName, urlAttr, requiredAttr) {
  const tagPattern = new RegExp(`<${tagName}\\b[^>]*>`, 'gi');
  return [...html.matchAll(tagPattern)]
    .map(match => match[0])
    .filter(tag => tag.toLowerCase().includes(requiredAttr))
    .map(tag => tag.match(new RegExp(`\\b${urlAttr}=["']([^"']+)["']`, 'i'))?.[1])
    .filter(url => url?.startsWith('/'));
}

async function fetchText(url, expectedContentType) {
  const response = await fetch(url);
  assert(response.ok, `${url} returned HTTP ${response.status}`);
  const contentType = response.headers.get('content-type') ?? '';
  assert(
    contentType.includes(expectedContentType),
    `${url} returned content-type ${contentType}, expected ${expectedContentType}`,
  );
  return await response.text();
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? host}`);
    const filePath = filePathForRequest(url.pathname);
    const bytes = await readFile(filePath);
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(bytes);
  } catch (error) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(error instanceof Error ? error.message : 'not found');
  }
});

await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, host, resolve);
});

try {
  const address = server.address();
  assert(address && typeof address === 'object', 'Smoke server did not bind to a TCP port');
  const baseUrl = `http://${host}:${address.port}`;

  const html = await fetchText(`${baseUrl}/`, 'text/html');
  assert(
    html.includes('<title>Typed spreadsheet incr_tea proof</title>'),
    'Built HTML is missing the incr_tea proof title',
  );
  assert(html.includes('id="app"'), 'Built HTML is missing the app mount node');

  const scriptUrls = localAssetUrls(html, 'script', 'src', 'type="module"');
  const stylesheetUrls = localAssetUrls(html, 'link', 'href', 'rel="stylesheet"');
  assert(scriptUrls.length > 0, 'Built HTML is missing a local module script');
  assert(stylesheetUrls.length > 0, 'Built HTML is missing a local stylesheet');

  const scripts = await Promise.all(
    scriptUrls.map(url => fetchText(`${baseUrl}${url}`, 'text/javascript')),
  );
  const stylesheets = await Promise.all(
    stylesheetUrls.map(url => fetchText(`${baseUrl}${url}`, 'text/css')),
  );

  assert(
    html.includes('side-by-side proof · incr_tea'),
    'Built HTML is missing the proof header copy',
  );
  assert(html.includes('id="app-evidence"'), 'Built HTML is missing the evidence mount node');
  assert(
    scripts.some(script => script.includes('50 by 50 typed spreadsheet proof grid')),
    'Built JS bundle is missing the proof grid view',
  );
  assert(
    stylesheets.some(stylesheet => stylesheet.includes('.proof-shell')),
    'Built CSS bundle is missing the proof shell styles',
  );

  console.log(`Smoke check passed for ${baseUrl}/`);
} finally {
  await new Promise(resolve => server.close(resolve));
}
