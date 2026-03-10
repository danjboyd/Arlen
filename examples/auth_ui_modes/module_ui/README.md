# Module-UI Auth Mode

Use `module-ui` when you want the stock auth flows but need them rendered inside
an app-owned guest shell.

## Config

```plist
authModule = {
  ui = {
    mode = "module-ui";
    layout = "layouts/guest";
    contextClass = "APPAuthUIContextHook";
    partials = {
      providerRow = "auth/partials/custom_provider_row";
    };
  };
};
```

## App-Owned Surface

- `templates/layouts/guest.html.eoc` for the surrounding guest shell
- an optional `ALNAuthModuleUIContextHook` class for page-level layout/context
- optional fine-grained partial overrides such as
  `templates/auth/partials/custom_provider_row.html.eoc`

## What Stays Module-Owned

- the auth page bodies by default
- the backend auth/session/provider/MFA flows
- the stable `/auth/api/...` JSON surface

This is the default-first path when the app wants branding and shell ownership
without fully forking the auth pages.
