import assert from 'node:assert/strict';
import test from 'node:test';
import register from '../common/pi/.pi/agent/extensions/protected-paths.ts';

const handlers = new Map();
register({ on: (event, handler) => handlers.set(event, handler) });
const check = handlers.get('tool_call');
assert.equal(typeof check, 'function');

const allowed = [
  'bff/test/integration-kit/coverage/recorder.ts',
  'src/dist/index.ts',
  'src/secrets.ts',
  'src/secrets.test.ts',
  'src/credentials.spec.ts',
  'src/credentials.py',
  'docs/id_rsa.md',
  'fixtures/id_rsa.pub',
  'fixtures/id_ed25519.pub',
];
const blocked = [
  '.env', 'project/.env.local', '.git/config',
  'node_modules/pkg/index.js', '.next/server.js', '.terraform/state',
  'keys/id_rsa', 'keys/id_ed25519', 'private.pem', 'private.key',
  'bundle.p12', 'bundle.pfx', 'secrets.json', 'secrets.yaml',
  'credentials.toml', 'secret.env', 'credentials',
  '.ssh/id_rsa', '.aws/credentials', '.docker/config.json',
];

for (const toolName of ['edit', 'write']) {
  test(`${toolName}: source names are allowed and sensitive paths stay blocked`, async () => {
    for (const path of allowed) {
      assert.equal(await check({ toolName, input: { path } }), undefined, path);
    }
    for (const path of blocked) {
      const result = await check({ toolName, input: { path } });
      assert.equal(result.block, true, path);
      assert.match(result.reason, /approval does not unlock/);
    }
  });
}

test('only target paths are checked, not source contents', async () => {
  assert.equal(await check({ toolName: 'write', input: {
    path: 'src/index.ts', content: 'credentials.json and .env',
  } }), undefined);
});
