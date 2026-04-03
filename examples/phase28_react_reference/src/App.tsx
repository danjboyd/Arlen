import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import {
  ArlenClient,
  arlenAdminResourceRegistry,
  arlenModuleRegistry,
  arlenResourceRegistry,
  arlenWorkspaceHints,
  buildUsersQueryParams,
  invalidateAfterCreateUser,
  publicUserCreateFormFields,
  type PublicUserCreateInput,
  useCreateUserMutation,
  useGetSessionQuery,
  useListUsersQuery,
  useSearchCapabilitiesQuery,
  usersResourceQueryContract,
  validatePublicUserCreateInput,
} from '../generated/arlen/src';

const baseUrl = (import.meta.env.VITE_ARLEN_BASE_URL as string | undefined) ?? 'http://127.0.0.1:3000';
const client = new ArlenClient({ baseUrl });

const initialDraft: PublicUserCreateInput = {
  email: '',
  displayName: '',
};

const visibleCreateFields = publicUserCreateFormFields.filter(
  (field) => !field.hasDefault && !field.readOnly
);

function resolveModuleOperationHint(
  moduleMeta: (typeof arlenModuleRegistry)[keyof typeof arlenModuleRegistry]
): string {
  if ('bootstrapOperationId' in moduleMeta && moduleMeta.bootstrapOperationId) {
    return moduleMeta.bootstrapOperationId;
  }
  if ('capabilityOperationId' in moduleMeta && moduleMeta.capabilityOperationId) {
    return moduleMeta.capabilityOperationId;
  }
  if ('summaryOperationId' in moduleMeta && moduleMeta.summaryOperationId) {
    return moduleMeta.summaryOperationId;
  }
  return 'no bootstrap op';
}

function serializeQueryParams(
  query: Record<string, string | number | boolean | null | Array<string | number | boolean | null>>
): string {
  const search = new URLSearchParams();
  for (const [key, rawValue] of Object.entries(query)) {
    const values = Array.isArray(rawValue) ? rawValue : [rawValue];
    for (const value of values) {
      search.append(key, value === null ? 'null' : String(value));
    }
  }
  return search.toString();
}

export function App() {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<PublicUserCreateInput>(initialDraft);
  const [emailFilter, setEmailFilter] = useState('');
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({});

  const sessionQuery = useGetSessionQuery(client, {});
  const searchCapabilitiesQuery = useSearchCapabilitiesQuery(client, {});
  const listUsersQuery = useListUsersQuery(client, {
    query: {
      limit: usersResourceQueryContract.pagination.defaultPageSize,
    },
  });
  const createUserMutation = useCreateUserMutation(client, {
    onSuccess: async () => {
      await invalidateAfterCreateUser(queryClient);
      setDraft(initialDraft);
      setValidationErrors({});
    },
  });

  const usersResource = arlenResourceRegistry.users;
  const usersAdmin = arlenAdminResourceRegistry.users;
  const adminColumns = usersAdmin?.defaultColumns ?? ['email', 'displayName'];
  const usersQueryPreview = serializeQueryParams(
    buildUsersQueryParams({
      select: ['id', 'email', 'displayName'],
      include: ['profile'],
      sort: [{ field: 'email', direction: 'asc' }],
      limit: usersResource.query?.pagination.defaultPageSize ?? 25,
      filter: emailFilter.length > 0 ? { email: emailFilter } : {},
    })
  );

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const validation = validatePublicUserCreateInput(draft);
    if (!validation.success) {
      const nextErrors: Record<string, string> = {};
      for (const issue of validation.errors) {
        if (nextErrors[issue.path]) {
          continue;
        }
        nextErrors[issue.path] = issue.message;
      }
      setValidationErrors(nextErrors);
      return;
    }

    setValidationErrors({});
    await createUserMutation.mutateAsync({
      body: {
        email: validation.value.email,
        ...(validation.value.displayName === null || validation.value.displayName === undefined
          ? {}
          : { displayName: validation.value.displayName }),
      },
    });
  }

  return (
    <div className="page-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Arlen Phase 28</p>
          <h1>Descriptor-first React contract workspace</h1>
          <p className="lede">
            This reference app consumes generated validators, query contracts,
            typed transport helpers, module metadata, and optional React hooks
            from one Arlen-owned source of truth.
          </p>
        </div>
        <dl className="hero-stats">
          <div>
            <dt>Package Manager</dt>
            <dd>{arlenWorkspaceHints.packageManager}</dd>
          </div>
          <div>
            <dt>Install</dt>
            <dd>{arlenWorkspaceHints.installCommand}</dd>
          </div>
          <div>
            <dt>Typecheck</dt>
            <dd>{arlenWorkspaceHints.typecheckCommand}</dd>
          </div>
        </dl>
      </header>

      <main className="grid">
        <section className="panel">
          <h2>Module Bootstrap</h2>
          <p className="panel-copy">
            Generated module metadata stays explicit. Auth, ops, and search all
            keep stable operation identifiers rather than hidden conventions.
          </p>
          <ul className="token-list">
            {Object.values(arlenModuleRegistry).map((moduleMeta) => (
              <li key={moduleMeta.name}>
                <strong>{moduleMeta.name}</strong>
                <span>{moduleMeta.kind}</span>
                <code>{resolveModuleOperationHint(moduleMeta)}</code>
              </li>
            ))}
          </ul>
          <div className="callout-grid">
            <article className="callout">
              <h3>Session</h3>
              <p>
                {sessionQuery.data?.authenticated
                  ? `Signed in as ${sessionQuery.data.user?.email ?? 'unknown'}`
                  : 'No authenticated session returned yet.'}
              </p>
            </article>
            <article className="callout">
              <h3>Search</h3>
              <p>
                {searchCapabilitiesQuery.data
                  ? `Modes: ${searchCapabilitiesQuery.data.supportedModes.join(', ')}`
                  : 'Capability metadata has not loaded yet.'}
              </p>
            </article>
          </div>
        </section>

        <section className="panel">
          <h2>Create User</h2>
          <p className="panel-copy">
            `validators.ts` contributes framework-neutral form metadata and
            create-input validation without turning ORM descriptors into a UI
            runtime.
          </p>
          <form className="stack" onSubmit={handleSubmit}>
            {visibleCreateFields.map((field) => {
              const fieldName = field.name as keyof PublicUserCreateInput;
              const currentValue = draft[fieldName];
              const error = validationErrors[field.name];
              return (
                <label className="field" key={field.name}>
                  <span>{field.label}</span>
                  <input
                    type={field.formatHint === 'email' ? 'email' : 'text'}
                    name={field.name}
                    value={typeof currentValue === 'string' ? currentValue : ''}
                    onChange={(event) =>
                      setDraft((current) => ({
                        ...current,
                        [fieldName]: event.target.value,
                      }))
                    }
                    placeholder={field.formatHint ?? field.inputKind}
                    readOnly={field.readOnly}
                    required={field.required}
                  />
                  {error ? <small className="error-text">{error}</small> : null}
                </label>
              );
            })}
            <div className="actions">
              <button type="submit" disabled={createUserMutation.isPending}>
                {createUserMutation.isPending ? 'Creating...' : 'Create User'}
              </button>
              {createUserMutation.error ? (
                <small className="error-text">
                  {createUserMutation.error instanceof Error
                    ? createUserMutation.error.message
                    : 'Create user failed'}
                </small>
              ) : null}
            </div>
          </form>
        </section>

        <section className="panel panel-wide">
          <div className="panel-header">
            <div>
              <h2>Users Resource</h2>
              <p className="panel-copy">
                `query.ts` and `meta.ts` expose allowed selects, includes, admin
                columns, and operation ownership as explicit frontend contracts.
              </p>
            </div>
            <label className="compact-filter">
              <span>Email Filter Preview</span>
              <input value={emailFilter} onChange={(event) => setEmailFilter(event.target.value)} />
            </label>
          </div>
          <div className="meta-strip">
            <span>Admin title field: {usersAdmin?.titleField ?? 'none'}</span>
            <span>Allowed include: {usersResource.query?.allowedInclude.join(', ') ?? 'none'}</span>
            <span>Default sort: {usersResource.query?.defaultSort.join(', ') ?? 'none'}</span>
          </div>
          <pre className="query-preview">?{usersQueryPreview}</pre>
          <p className="footnote">
            This preview comes from `buildUsersQueryParams()`. It stays additive:
            matching params still need to exist in OpenAPI if you want them to
            flow directly into `client.ts` request types.
          </p>
          <div className="table-shell">
            <table>
              <thead>
                <tr>
                  {adminColumns.map((column) => (
                    <th key={column}>{column}</th>
                  ))}
                  <th>id</th>
                </tr>
              </thead>
              <tbody>
                {listUsersQuery.data?.items.map((user) => (
                  <tr key={user.id}>
                    {adminColumns.map((column) => (
                      <td key={column}>
                        {column === 'email'
                          ? user.email
                          : column === 'displayName'
                            ? user.displayName ?? 'Unnamed'
                            : 'n/a'}
                      </td>
                    ))}
                    <td className="mono">{user.id}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!listUsersQuery.data && !listUsersQuery.isPending ? (
              <p className="footnote">No list payload has been returned yet.</p>
            ) : null}
          </div>
        </section>
      </main>
    </div>
  );
}
