import { readFile, writeFile } from 'node:fs/promises';

async function replaceExactlyOnce(path, before, after) {
  const source = await readFile(path, 'utf8');
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`${path}: expected exactly one match for AIO loopback patch`);
  }
  await writeFile(path, source.slice(0, first) + after + source.slice(first + before.length));
}

await replaceExactlyOnce(
  '/app/docker/redis-rest-proxy.mjs',
  "server.listen(PORT, '0.0.0.0', () => {\n  console.log(`Redis REST proxy listening on 0.0.0.0:${PORT}`);",
  "server.listen(PORT, process.env.REDIS_REST_HOST || '127.0.0.1', () => {\n  console.log(`Redis REST proxy listening on ${process.env.REDIS_REST_HOST || '127.0.0.1'}:${PORT}`);",
);

await replaceExactlyOnce(
  '/app/scripts/ais-relay.cjs',
  'server.listen(PORT, () => {',
  "server.listen(PORT, process.env.RELAY_HOST || '127.0.0.1', () => {",
);
