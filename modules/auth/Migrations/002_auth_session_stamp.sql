-- Per-user session generation. Sessions record the value current at sign-in;
-- incrementing it ends every existing session for that user.
ALTER TABLE auth_users ADD COLUMN IF NOT EXISTS session_stamp BIGINT NOT NULL DEFAULT 0;
