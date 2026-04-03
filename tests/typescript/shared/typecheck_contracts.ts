import type { ListUsersRequest, PublicUserCreateInput } from '../generated/arlen/src/index.ts';
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

// @ts-expect-error invalid include values must fail closed.
buildUsersQueryParams({ include: ['notARelation'] });

// @ts-expect-error invalid sort fields must fail closed.
buildUsersQueryParams({ sort: [{ field: 'notAField' }] });

// @ts-expect-error undeclared headers must not become implicit request surface.
const invalidRequest: ListUsersRequest = { headers: { authorization: 'Bearer token' } };

void invalidRequest;
