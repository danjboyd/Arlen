# Headless Auth UI Mode

Use `headless` when the app owns all auth presentation and only wants the
module backend contract.

## Config

```plist
authModule = {
  ui = {
    mode = "headless";
  };
};
```

## What Changes

- module-owned auth HTML routes such as `/auth/login` and `/auth/register` are
  suppressed
- `/auth/api/...` remains the stable session/auth/provider surface
- provider login bootstrap and callback completion still run through the module

## App-Owned Surface

- your SPA, native client, or custom frontend owns the auth screens
- no app templates are required under `templates/auth/...`
- auth state discovery still comes from `/auth/api/session`
