-- Signed-out sessions. Sessions are signed cookies, so signing out records the
-- session's identifier here and the per-request session lookup refuses any
-- other copy of that cookie. Rows are only needed until the cookie would have
-- expired anyway; expired rows are removed opportunistically.
CREATE TABLE IF NOT EXISTS auth_revoked_sessions (
  session_id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS auth_revoked_sessions_expires_idx ON auth_revoked_sessions (expires_at);
