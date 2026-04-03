import assert from 'node:assert/strict';
import test from 'node:test';

import type { QueryClient } from '@tanstack/react-query';

import type { ArlenClient } from '../generated/arlen/src/client.ts';
import {
  arlenInvalidationHints,
  arlenMutationKeys,
  arlenQueryKeyRoots,
  arlenQueryKeys,
  createUserMutationOptions,
  invalidateAfterCreateUser,
  invalidateAfterUpdateUser,
  listUsersQueryOptions,
} from '../generated/arlen/src/react.ts';

test('query and mutation keys remain deterministic and request-shaped', () => {
  assert.deepEqual(arlenQueryKeyRoots.listUsers, ['listUsers']);
  assert.deepEqual(arlenQueryKeys.listUsers({ query: { limit: 25 } }), [
    'listUsers',
    {
      limit: 25,
    },
  ]);
  assert.deepEqual(
    arlenQueryKeys.getUser({
      path: {
        id: 'user-1',
      },
      query: {
        includePosts: true,
      },
    }),
    [
      'getUser',
      {
        id: 'user-1',
      },
      {
        includePosts: true,
      },
    ]
  );
  assert.deepEqual(arlenMutationKeys.createUser, ['createUser']);
  assert.deepEqual(arlenInvalidationHints.createUser.queryOperations, ['listUsers', 'getUser']);
});

test('query and mutation option helpers delegate to the typed client surface', async () => {
  const listCalls: Array<Record<string, unknown>> = [];
  const createCalls: Array<Record<string, unknown>> = [];
  const client = {
    createUser: async (request: Record<string, unknown>) => {
      createCalls.push(request);
      return {
        data: {
          email: 'created@example.com',
          id: 'created-user',
        },
      };
    },
    listUsers: async (request: Record<string, unknown>) => {
      listCalls.push(request);
      return {
        items: [],
      };
    },
  } as unknown as ArlenClient;

  const queryOptions = listUsersQueryOptions(
    client,
    {
      query: {
        limit: 3,
      },
    },
    {
      staleTime: 500,
    }
  );
  assert.equal(queryOptions.staleTime, 500);
  assert.deepEqual(queryOptions.queryKey, ['listUsers', { limit: 3 }]);
  await queryOptions.queryFn();
  assert.equal(listCalls.length, 1);

  const mutationOptions = createUserMutationOptions(client);
  assert.deepEqual(mutationOptions.mutationKey, ['createUser']);
  await mutationOptions.mutationFn({
    body: {
      email: 'created@example.com',
    },
  });
  assert.equal(createCalls.length, 1);
});

test('invalidation helpers target list and detail roots only', async () => {
  const invalidations: Array<readonly unknown[]> = [];
  const queryClient = {
    invalidateQueries: async ({ queryKey }: { queryKey: readonly unknown[] }) => {
      invalidations.push(queryKey);
    },
  } as unknown as QueryClient;

  await invalidateAfterCreateUser(queryClient);
  await invalidateAfterUpdateUser(queryClient);

  assert.deepEqual(invalidations, [
    arlenQueryKeyRoots.listUsers,
    arlenQueryKeyRoots.getUser,
    arlenQueryKeyRoots.listUsers,
    arlenQueryKeyRoots.getUser,
  ]);
});
