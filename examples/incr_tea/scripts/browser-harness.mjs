import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = fileURLToPath(new URL('.', import.meta.url));

const repoRoot = resolve(scriptDir, '../../..');
export const host = '127.0.0.1';

export function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

function filePathForRequest(pathname, defaultPath) {
  const localPath = pathname === '/' ? defaultPath : decodeURIComponent(pathname);
  const filePath = resolve(repoRoot, `.${localPath}`);
  assert(
    filePath === repoRoot || filePath.startsWith(`${repoRoot}${sep}`),
    `Refusing to serve path outside repo: ${pathname}`,
  );
  return filePath;
}

export function createStaticServer(defaultPath) {
  return createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', `http://${request.headers.host ?? host}`);
      const filePath = filePathForRequest(url.pathname, defaultPath);
      const bytes = await readFile(filePath);
      response.writeHead(200, { 'content-type': contentType(filePath) });
      response.end(bytes);
    } catch (error) {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end(error instanceof Error ? error.message : 'not found');
    }
  });
}

export function listen(server) {
  return new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, host, resolveListen);
  });
}

export function close(server) {
  return new Promise(resolveClose => server.close(resolveClose));
}
