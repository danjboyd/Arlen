import assert from 'node:assert/strict';
import test from 'node:test';

import { ArlenClient } from '../generated/arlen/src/client.ts';
import { buildUsersQueryParams, usersResourceQueryContract } from '../generated/arlen/src/query.ts';
import { validatePublicUserCreateInput } from '../generated/arlen/src/validators.ts';

const baseUrl = process.env.ARLEN_PHASE28_BASE_URL;

function updateCookieJar(cookieJar: Map<string, string>, cookieHeader: string): void {
  const cookiePair = cookieHeader.split(';', 1)[0]?.trim();
  if (!cookiePair) {
    return;
  }
  const separatorIndex = cookiePair.indexOf('=');
  if (separatorIndex <= 0) {
    return;
  }
  cookieJar.set(cookiePair.slice(0, separatorIndex), cookiePair.slice(separatorIndex + 1));
}

function createCookieAwareFetch(): typeof fetch {
  const cookieJar = new Map<string, string>();
  return async (input, init) => {
    const headers = new Headers(init?.headers ?? {});
    if (cookieJar.size > 0 && !headers.has('cookie')) {
      headers.set(
        'cookie',
        [...cookieJar.entries()].map(([name, value]) => `${name}=${value}`).join('; ')
      );
    }

    const response = await fetch(input, {
      ...init,
      headers,
    });

    const responseHeaders = response.headers as Headers & { getSetCookie?: () => string[] };
    const setCookies = responseHeaders.getSetCookie?.() ?? [];
    if (setCookies.length > 0) {
      for (const cookieHeader of setCookies) {
        updateCookieJar(cookieJar, cookieHeader);
      }
      return response;
    }

    const singleCookieHeader = response.headers.get('set-cookie');
    if (singleCookieHeader) {
      updateCookieJar(cookieJar, singleCookieHeader);
    }
    return response;
  };
}

test('generated client supports back-office CRUD flows against a live Arlen app', async (t) => {
  if (!baseUrl) {
    t.skip('ARLEN_PHASE28_BASE_URL is not set');
    return;
  }

  const cookieFetch = createCookieAwareFetch();
  let csrfToken = '';
  const client = new ArlenClient({
    baseUrl,
    fetch: cookieFetch,
    headers: async () => (csrfToken ? { 'x-csrf-token': csrfToken } : {}),
  });
  const session = await client.getSession({});
  assert.equal(session.authenticated, true);
  assert.equal(typeof session.session.csrfToken, 'string');
  csrfToken = session.session.csrfToken;

  const before = await client.listUsers({
    headers: {
      'x-tenant-id': 'backoffice',
    },
    query: {
      limit: usersResourceQueryContract.pagination.defaultPageSize,
    },
  });

  const draft = {
    displayName: 'Phase 28 Integration User',
    email: `phase28-${Date.now()}@example.com`,
  };
  const validation = validatePublicUserCreateInput(draft);
  assert.equal(validation.success, true);
  if (!validation.success) {
    return;
  }

  const created = await client.createUser({
    body: validation.value,
  });
  assert.equal(created.meta?.created, true);

  const detail = await client.getUser({
    path: {
      id: created.data.id,
    },
    query: {
      includePosts: true,
    },
  });
  assert.equal(detail.data.email, draft.email);

  const updated = await client.updateUser({
    body: {
      active: true,
      displayName: 'Phase 28 Integration User Updated',
    },
    path: {
      id: created.data.id,
    },
  });
  assert.equal(updated.data.displayName, 'Phase 28 Integration User Updated');

  const after = await client.listUsers({
    query: {
      limit: usersResourceQueryContract.pagination.maxPageSize,
    },
  });
  assert.ok(after.items.length >= before.items.length);
  assert.ok(after.items.some((entry) => entry.id === created.data.id));
});

test('generated detail, query, and capability helpers match customer-facing live flows', async (t) => {
  if (!baseUrl) {
    t.skip('ARLEN_PHASE28_BASE_URL is not set');
    return;
  }

  const client = new ArlenClient({ baseUrl });
  const listed = await client.listUsers({
    query: {
      limit: 1,
    },
  });
  const firstUser = listed.items[0];
  assert.ok(firstUser, 'expected seeded Phase 28 reference data');
  if (!firstUser) {
    return;
  }

  const detail = await client.getUser({
    path: {
      id: firstUser.id,
    },
    query: {
      includePosts: true,
    },
  });
  assert.ok(detail.data.profile);
  assert.ok((detail.data.posts ?? []).length >= 1);

  const ops = await client.opsSummary({});
  assert.equal(ops.status, 'ok');
  assert.ok(ops.uptimeSeconds >= 0);

  const search = await client.searchCapabilities({});
  assert.equal(search.supportsHighlighting, true);
  assert.deepEqual(search.supportedModes, ['fulltext', 'prefix']);

  const preview = buildUsersQueryParams({
    filter: {
      email: firstUser.email,
    },
    include: ['profile'],
    limit: 5,
    select: ['id', 'email'],
    sort: [
      {
        direction: 'asc',
        field: 'email',
      },
    ],
  });
  assert.deepEqual(preview.include, ['profile']);
  assert.deepEqual(preview.fields, ['id', 'email']);
});
