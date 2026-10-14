import { test } from 'node:test';
import assert from 'node:assert/strict';
test('runs inside the working directory', () => assert.ok(process.cwd().replaceAll('\\', '/').endsWith('fixtures/js-sub/app')));
