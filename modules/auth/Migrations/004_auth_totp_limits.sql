-- Remember the last accepted TOTP time step for each enrollment so a code
-- cannot be accepted twice, even from a different session.
ALTER TABLE auth_mfa_enrollments ADD COLUMN IF NOT EXISTS last_used_step BIGINT;

-- Per-account failure counters for MFA verification (TOTP and recovery codes)
-- and local password sign-in. A row is reset when verification succeeds.
CREATE TABLE IF NOT EXISTS auth_attempt_limits (
  user_id BIGINT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  last_failure_at TIMESTAMPTZ,
  locked_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, scope)
);
