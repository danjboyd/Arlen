import assert from 'node:assert/strict';
import test from 'node:test';

import { ArlenClient, ArlenClientError } from '../generated/arlen/src/client.ts';
import { createJSONResponse } from '../shared/phase28_support.ts';

test('ArlenClient serializes request bodies and merges default headers', async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const client = new ArlenClient({
    baseUrl: 'http://127.0.0.1:4100/',
    fetch: async (url, init) => {
      calls.push({ init: init ?? {}, url: String(url) });
      return createJSONResponse({
        data: {
          displayName: 'Updated Name',
          email: 'ops@example.com',
          id: 'user-123',
        },
        meta: {
          updated: true,
        },
      });
    },
    headers: async () => ({
      authorization: 'Bearer integration-token',
    }),
  });

  const response = await client.updateUser({
    body: {
      active: true,
      displayName: 'Updated Name',
    },
    path: {
      id: 'user/123',
    },
  });

  assert.equal(response.meta?.updated, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, 'http://127.0.0.1:4100/api/users/user%2F123');
  assert.equal(calls[0]?.init.method, 'PATCH');
  assert.deepEqual(JSON.parse(String(calls[0]?.init.body ?? 'null')), {
    active: true,
    displayName: 'Updated Name',
  });
  assert.deepEqual(calls[0]?.init.headers, {
    accept: 'application/json',
    authorization: 'Bearer integration-token',
    'content-type': 'application/json',
  });
});

test('ArlenClient keeps query and declared header inputs explicit', async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const client = new ArlenClient({
    baseUrl: 'http://127.0.0.1:4200',
    fetch: async (url, init) => {
      calls.push({ init: init ?? {}, url: String(url) });
      return createJSONResponse({
        items: [],
        nextCursor: null,
        totalCount: 0,
      });
    },
  });

  await client.listUsers({
    headers: {
      'x-tenant-id': 'tenant-a',
    },
    query: {
      cursor: 'cursor-7',
      limit: 5,
    },
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, 'http://127.0.0.1:4200/api/users?cursor=cursor-7&limit=5');
  assert.deepEqual(calls[0]?.init.headers, {
    accept: 'application/json',
    'x-tenant-id': 'tenant-a',
  });
});

test('ArlenClientError preserves operation metadata and parsed error payloads', async () => {
  const client = new ArlenClient({
    baseUrl: 'http://127.0.0.1:4300',
    fetch: async () =>
      createJSONResponse(
        {
          error: {
            code: 'duplicate_email',
            message: 'Email already exists',
          },
        },
        {
          status: 409,
        }
      ),
  });

  await assert.rejects(
    () =>
      client.createUser({
        body: {
          email: 'duplicate@example.com',
        },
      }),
    (error: unknown) => {
      assert.ok(error instanceof ArlenClientError);
      assert.equal(error.operationId, 'create_user');
      assert.equal(error.status, 409);
      assert.deepEqual(error.payload, {
        error: {
          code: 'duplicate_email',
          message: 'Email already exists',
        },
      });
      return true;
    }
  );
});
