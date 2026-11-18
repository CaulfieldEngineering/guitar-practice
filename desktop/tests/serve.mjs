// A drill server for the desktop sync test: the real one (server/index.mjs createApp) on a port and a data folder of
// the test's own, so the test never touches the live runs.  node desktop/tests/serve.mjs <port> <data folder>
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from '../../server/index.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const [port, data] = process.argv.slice(2);
http.createServer(createApp({ catalog: path.join(ROOT, 'catalog'), data, voice: path.join(ROOT, 'voice'), releases: path.join(data, 'releases') }))
  .listen(Number(port), '127.0.0.1', () => console.log('ready'));
