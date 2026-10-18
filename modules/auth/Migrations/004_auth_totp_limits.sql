-- Remember the last accepted TOTP time step for each enrollment so a code
-- cannot be accepted twice, even from a different session.
ALTER TABLE auth_mfa_enrollments ADD COLUMN IF NOT EXISTS last_used_step BIGINT;

-- Per-account failure counters for MFA verification (TOTP and recovery codes).
-- A row is reset when verification succeeds.
CREATE TABLE IF NOT EXISTS auth_attempt_limits (
  user_id BIGINT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  last_failure_at TIMESTAMPTZ,
  locked_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, scope)
);

-- Password sign-in failure counters, keyed by a SHA-256 of the submitted
-- (normalized) email so they work the same whether or not the account exists.
-- client_ip is the client address, or '*' for the account-wide row.
CREATE TABLE IF NOT EXISTS auth_password_attempts (
  key_hash TEXT NOT NULL,
  client_ip TEXT NOT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  delayed_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (key_hash, client_ip)
);

CREATE INDEX IF NOT EXISTS auth_password_attempts_updated_idx ON auth_password_attempts (updated_at);
