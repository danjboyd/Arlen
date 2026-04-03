import assert from 'node:assert/strict';
import test from 'node:test';

import { arlenOperations } from '../generated/arlen/src/client.ts';
import {
  arlenModuleRegistry,
  arlenResourceRegistry,
  arlenWorkspaceHints,
} from '../generated/arlen/src/meta.ts';
import {
  publicUserRelationContracts,
  usersResourceQueryContract,
} from '../generated/arlen/src/query.ts';
import {
  createUserRequestSchema,
  publicUserCreateFormFields,
  validatePublicUserCreateInput,
} from '../generated/arlen/src/validators.ts';
import { readRepoJSON } from '../shared/phase28_support.ts';

interface OpenAPIPathOperation {
  readonly operationId?: string;
}

interface Phase28OpenAPIFixture {
  readonly paths: Record<string, Record<string, OpenAPIPathOperation>>;
  readonly ['x-arlen']: {
    readonly modules: Array<Record<string, unknown>>;
    readonly resources: Array<Record<string, unknown>>;
    readonly workspace: Record<string, string>;
  };
}

test('workspace, module, and resource metadata match x-arlen fixture contracts', () => {
  const fixture = readRepoJSON<Phase28OpenAPIFixture>('tests/fixtures/phase28/openapi_contract.json');
  const workspace = fixture['x-arlen'].workspace;
  const resource = fixture['x-arlen'].resources[0] ?? {};
  const resourceQuery = (resource.query as Record<string, unknown>) ?? {};
  const resourceOperations = (resource.operations as Record<string, unknown>) ?? {};
  const resourceAdmin = (resource.admin as Record<string, unknown>) ?? {};
  const authModule = fixture['x-arlen'].modules.find((entry) => entry.name === 'auth') ?? {};

  assert.deepEqual(arlenWorkspaceHints, {
    devCommand: workspace.dev_command,
    installCommand: workspace.install_command,
    manifestPath: 'db/schema/arlen_typescript.json',
    outputDir: 'frontend/generated/arlen',
    packageManager: workspace.package_manager,
    typecheckCommand: workspace.typecheck_command,
  });

  assert.deepEqual(usersResourceQueryContract.allowedSelect, resourceQuery.allowed_select);
  assert.deepEqual(usersResourceQueryContract.allowedInclude, resourceQuery.allowed_include);
  assert.deepEqual(usersResourceQueryContract.sortableFields, resourceQuery.sortable_fields);
  assert.deepEqual(usersResourceQueryContract.filterableFields, resourceQuery.filterable_fields);
  assert.deepEqual(usersResourceQueryContract.defaultSort, resourceQuery.default_sort);
  assert.equal(usersResourceQueryContract.pagination.defaultPageSize, resourceQuery.default_page_size);
  assert.equal(usersResourceQueryContract.pagination.maxPageSize, resourceQuery.max_page_size);
  assert.equal(arlenResourceRegistry.users.operations.list, resourceOperations.list);
  assert.equal(arlenResourceRegistry.users.admin?.htmlPath, resourceAdmin.html_path);
  assert.equal(arlenModuleRegistry.auth.bootstrapOperationId, authModule.bootstrap_operation_id);
});

test('validator, relation, and operation surfaces stay aligned with fixture contracts', () => {
  const fixture = readRepoJSON<Phase28OpenAPIFixture>('tests/fixtures/phase28/openapi_contract.json');
  const fixtureOperationIDs = Object.values(fixture.paths)
    .flatMap((pathItem) => Object.values(pathItem))
    .map((operation) => operation.operationId ?? '')
    .filter((operationId) => operationId.length > 0)
    .sort();
  const generatedOperationIDs = Object.values(arlenOperations)
    .map((operation) => operation.operationId)
    .sort();

  assert.deepEqual(generatedOperationIDs, fixtureOperationIDs);
  assert.deepEqual(Object.keys(publicUserRelationContracts).sort(), ['posts', 'profile']);
  assert.deepEqual([...usersResourceQueryContract.allowedInclude].sort(), ['posts', 'profile']);
  assert.deepEqual(
    publicUserCreateFormFields.map((field) => field.name).sort(),
    ['displayName', 'email', 'id']
  );
  const idField = publicUserCreateFormFields.find((field) => field.name === 'id');
  assert.ok(idField);
  assert.equal(idField.hasDefault, true);
  assert.equal(idField.required, false);

  const requestBodySchema = createUserRequestSchema.properties?.body;
  assert.ok(requestBodySchema && typeof requestBodySchema === 'object' && !Array.isArray(requestBodySchema));
  const bodySchema = requestBodySchema as unknown as Record<string, unknown>;
  assert.deepEqual(bodySchema.requiredFields, ['email']);
  const bodyProperties = bodySchema.properties as Record<string, Record<string, unknown>> | undefined;
  const roleSchema = bodyProperties?.role;
  assert.ok(roleSchema);
  assert.deepEqual(roleSchema.literalValues, ['author', 'admin']);

  const valid = validatePublicUserCreateInput({
    displayName: 'Fixture User',
    email: 'fixture@example.com',
  });
  assert.equal(valid.success, true);

  const invalid = validatePublicUserCreateInput({
    displayName: 'Missing Email',
    unexpected: true,
  });
  assert.equal(invalid.success, false);
  assert.deepEqual(
    invalid.success ? [] : invalid.errors.map((entry) => entry.code).sort(),
    ['required', 'unknown_field']
  );
});
