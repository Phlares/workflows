import { test } from 'node:test';
import assert from 'node:assert/strict';
test('always fails', () => assert.fail('expected failure from fixture'));
