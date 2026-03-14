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

## Embedding MFA Fragments In App Pages

Phase 18 adds a coarse embeddable fragment contract for server-rendered EOC
apps. A typical account/security controller can ask the runtime for fragment
context:

```objc
NSDictionary *fragmentContext = [[ALNAuthModuleRuntime sharedRuntime]
    mfaManagementFragmentContextForCurrentUserInContext:ctx
                                      returnTo:@"/account/security"
                                         error:&error];
```

Then an app-owned template can render the stock factor inventory plus the
appropriate MFA fragments:

```eoc
<% if (!ALNEOCInclude(out, ctx, @"modules/auth/fragments/mfa_factor_inventory_panel", error)) { return nil; } %>
<% if ([[ctx objectForKey:@"authTOTPNeedsEnrollment"] boolValue]) { %>
  <% if (!ALNEOCInclude(out, ctx, @"modules/auth/fragments/mfa_enrollment_panel", error)) { return nil; } %>
<% } %>
<% if ([[[ctx objectForKey:@"authSMSState"] objectForKey:@"enabled"] boolValue]) { %>
  <% if (!ALNEOCInclude(out, ctx, @"modules/auth/fragments/mfa_sms_enrollment_panel", error)) { return nil; } %>
<% } %>
```

That keeps the MFA UI aligned with the stock auth module pages without forcing
the app to adopt the full `/auth/...` page surface.
