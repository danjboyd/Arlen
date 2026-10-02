-- Arlen durable jobs schema v1. Keep in sync with +schemaStatements.
BEGIN;
SELECT pg_advisory_xact_lock(714182639041);
CREATE TABLE IF NOT EXISTS arlen_job_schema (version integer PRIMARY KEY CHECK (version = 1));
INSERT INTO arlen_job_schema(version) VALUES(1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS arlen_job_queues (namespace text NOT NULL, queue text NOT NULL, state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','draining')), PRIMARY KEY(namespace,queue));
CREATE TABLE IF NOT EXISTS arlen_jobs (namespace text NOT NULL, job_id text NOT NULL, sequence bigserial NOT NULL, name text NOT NULL, payload jsonb NOT NULL, queue text NOT NULL, state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','leased','completed','failed')), attempt integer NOT NULL DEFAULT 0 CHECK(attempt >= 0), max_attempts integer NOT NULL CHECK(max_attempts > 0), not_before timestamptz NOT NULL DEFAULT clock_timestamp(), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(), lease_token text, lease_expires_at timestamptz, idempotency_key text, retain_deduplication boolean NOT NULL DEFAULT false, result jsonb, failure_message text, replay_of text, PRIMARY KEY(namespace,job_id), FOREIGN KEY(namespace,queue) REFERENCES arlen_job_queues(namespace,queue), CHECK ((state = 'leased') = (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)));
CREATE UNIQUE INDEX IF NOT EXISTS arlen_jobs_deduplication ON arlen_jobs(namespace,idempotency_key) WHERE idempotency_key IS NOT NULL AND (state IN ('pending','leased') OR retain_deduplication);
CREATE INDEX IF NOT EXISTS arlen_jobs_due ON arlen_jobs(namespace,queue,not_before,sequence) WHERE state = 'pending';
CREATE INDEX IF NOT EXISTS arlen_jobs_expiry ON arlen_jobs(namespace,lease_expires_at) WHERE state = 'leased';
COMMIT;
