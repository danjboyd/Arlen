# Generated-App-UI Auth Mode

Use `generated-app-ui` when the app should own the auth templates and assets
fully while keeping the first-party auth backend contract.

## Bootstrap

```bash
./build/arlen module add auth
./build/arlen module eject auth-ui --json
./build/arlen module migrate --env development
```

## Config After Eject

```plist
authModule = {
  ui = {
    mode = "generated-app-ui";
    layout = "layouts/auth_generated";
    generatedPagePrefix = "auth";
  };
};
```

## Generated Files

- `templates/auth/login.html.eoc`
- `templates/auth/register.html.eoc`
- `templates/auth/password/forgot.html.eoc`
- `templates/auth/password/reset.html.eoc`
- `templates/auth/mfa/manage.html.eoc`
- `templates/auth/mfa/sms.html.eoc`
- `templates/auth/mfa/totp.html.eoc`
- `templates/auth/mfa/totp_enrollment.html.eoc`
- `templates/auth/mfa/totp_recovery_codes.html.eoc`
- `templates/auth/result.html.eoc`
- `templates/auth/fragments/...`
- `templates/auth/partials/...`
- `templates/layouts/auth_generated.html.eoc`
- `public/auth/auth.css`
- `public/auth/auth_totp_qr.js`

## Contract Notes

- the app edits the generated templates, partials, layout, and CSS
- the module still owns routes, session semantics, provider login, MFA, and
  `/auth/api/...`
- when SMS MFA is enabled in app config, the generated MFA templates already
  include the stock factor-inventory and SMS-management fragments
- moving to this mode does not require controller or route rewiring
