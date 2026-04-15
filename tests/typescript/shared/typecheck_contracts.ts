import type { ListUsersRequest, PublicUserCreateInput } from '../generated/arlen/src/index.ts';
import type { ArlenRealtimeClientOptions, ArlenRealtimeEventEnvelope } from '../generated/arlen/src/index.ts';
import {
  buildUsersQueryParams,
  usersResourceQueryContract,
} from '../generated/arlen/src/query.ts';
import { arlenModuleRegistry } from '../generated/arlen/src/meta.ts';

const validDraft: PublicUserCreateInput = {
  email: 'compile-only@example.com',
  displayName: 'Compile Only',
};

const validRequest: ListUsersRequest = {
  headers: {
    'x-tenant-id': 'tenant-42',
  },
  query: {
    limit: usersResourceQueryContract.pagination.defaultPageSize,
  },
};

const validParams = buildUsersQueryParams({
  filter: {
    email: validDraft.email,
  },
  include: ['profile'],
  limit: 10,
  select: ['id', 'email'],
  sort: [
    {
      direction: 'asc',
      field: 'email',
    },
  ],
});

void validRequest;
void validParams;
void arlenModuleRegistry.auth.bootstrapOperationId;

const realtimeOptions: ArlenRealtimeClientOptions = {
  streamId: 'conversation:33',
  transports: ['websocket', 'sse', 'poll'],
};

const realtimeEnvelope: ArlenRealtimeEventEnvelope<{ body: string }> = {
  stream_id: 'conversation:33',
  sequence: 1,
  event_id: 'evt_1',
  event_type: 'message_created',
  occurred_at: '2026-04-15T21:00:00Z',
  payload: {
    body: 'compile only',
  },
};

void realtimeOptions;
void realtimeEnvelope;

// @ts-expect-error invalid include values must fail closed.
buildUsersQueryParams({ include: ['notARelation'] });

// @ts-expect-error invalid sort fields must fail closed.
buildUsersQueryParams({ sort: [{ field: 'notAField' }] });

// @ts-expect-error undeclared headers must not become implicit request surface.
const invalidRequest: ListUsersRequest = { headers: { authorization: 'Bearer token' } };

void invalidRequest;
