# Systemd Runbook

This runbook documents the recommended VM/`systemd` shape for Arlen apps using
`propane`.

The repository ships reference files under `tools/deploy/systemd/`:

- `arlen@.service`: base production unit template
- `arlen-debug.conf`: incident/debug drop-in
- `site.env.example`: per-site production environment file
- `site.debug.env.example`: per-site incident/debug environment file

When a deploy target requires GNUstep env sourcing, `arlen deploy init <target>`
also generates concrete wrapper scripts under
`build/deploy/targets/<target>/bin/` that source the declared GNUstep script
before execing packaged `propane` / `jobs-worker`.

The recommended pattern is one base unit plus a temporary debug override. Do
not keep separate long-lived "normal" and "debug" service units in sync.

## 1. Layout Assumption

The reference unit assumes this release layout:

```text
/srv/arlen/<site>/releases/current/
  app/
  framework/
```

That matches Arlen's release workflow in `docs/DEPLOYMENT.md`.

If your deployment root differs, copy `tools/deploy/systemd/arlen@.service`
and adjust the paths before installing it into `/etc/systemd/system/`.
The reference template also assumes the service account is `arlen:arlen`; edit
`User=` and `Group=` if your host uses a different runtime user.

For GNUstep-backed targets, prefer the generated unit from
`arlen deploy init <target>` over hand-copying the raw template. The generated
unit bakes in the target release root, env file, and wrapper choice.

## 2. Install the Base Unit

```bash
sudo install -d /etc/arlen
sudo install -m 0644 tools/deploy/systemd/arlen@.service /etc/systemd/system/
sudo install -m 0600 tools/deploy/systemd/site.env.example /etc/arlen/myapp.env
sudoedit /etc/arlen/myapp.env
sudo systemctl daemon-reload
sudo systemctl enable --now arlen@myapp
```

The base unit already enables:

- JSON logs
- request timing logs
- trace/correlation headers
- health/readiness details
- startup-gated readiness
- metrics
- `propane` under `Restart=always`
- journald capture for both `stdout` and `stderr`
- core dumps via `LimitCORE=infinity`

That gives you:

- Arlen request-complete JSON logs in journald
- Arlen error logs in journald
- `propane:lifecycle ...` manager/worker diagnostics in journald
- crash dump availability through your host `coredumpctl` pipeline

Arlen reserves `/healthz`, `/readyz`, `/livez`, `/metrics`, and `/clusterz`
ahead of app route dispatch, so the deploy/runbook probe paths in this guide
remain valid even when apps register broad catch-all routes.

## 3. Base Environment File

Copy `tools/deploy/systemd/site.env.example` to `/etc/arlen/<site>.env` and
set at least:

- `ARLEN_DATABASE_URL`
- `ARLEN_SESSION_SECRET` when sessions are enabled
- any instance-specific host/port overrides
- any cluster or async-job overrides you need

Example:

```bash
sudoedit /etc/arlen/myapp.env
```

## 4. Enable Debug Mode

Enable debug mode with a drop-in, not a second service unit:

```bash
sudo install -d /etc/systemd/system/arlen@myapp.service.d
sudo install -m 0644 tools/deploy/systemd/arlen-debug.conf \
  /etc/systemd/system/arlen@myapp.service.d/debug.conf
sudo install -m 0600 tools/deploy/systemd/site.debug.env.example \
  /etc/arlen/myapp.debug.env
sudoedit /etc/arlen/myapp.debug.env
sudo systemctl daemon-reload
sudo systemctl restart arlen@myapp
```

The drop-in raises verbosity and loads `/etc/arlen/<site>.debug.env` for
incident-only overrides such as:

- `ARLEN_LOG_LEVEL=debug`
- `ARLEN_PROPANE_LIFECYCLE_LOG=/var/log/arlen/<site>-propane-lifecycle.log`
- temporary dispatch/backpressure overrides

## 5. Disable Debug Mode

```bash
sudo rm -f /etc/systemd/system/arlen@myapp.service.d/debug.conf
sudo rm -f /etc/arlen/myapp.debug.env
sudo systemctl daemon-reload
sudo systemctl restart arlen@myapp
```

If you want to keep the file around for future incidents, rename it instead of
deleting it.

## 6. Normal Incident Workflow

1. Confirm the process manager is healthy:

```bash
systemctl status arlen@myapp
journalctl -u arlen@myapp -n 200 --no-pager
./build/arlen deploy status --service arlen@myapp --releases-dir /srv/arlen/myapp/releases --json
./build/arlen deploy logs --service arlen@myapp --lines 200
```

2. Check the built-in probes:

```bash
curl -fsS http://127.0.0.1:3000/healthz
curl -fsS -H 'Accept: application/json' http://127.0.0.1:3000/readyz
curl -fsS http://127.0.0.1:3000/metrics
./build/arlen deploy doctor --service arlen@myapp --base-url http://127.0.0.1:3000 \
  --releases-dir /srv/arlen/myapp/releases --json
```

3. If you installed the `ops` module, inspect `/ops` or `/ops/api/{summary,signals,metrics}`.

4. If you need more detail, enable the debug drop-in, reproduce once, collect:

- `journalctl -u arlen@myapp`
- any `ARLEN_PROPANE_LIFECYCLE_LOG` file you configured
- proxy logs correlated by `X-Request-Id` / `X-Correlation-Id`
- `coredumpctl info` output if there was a crash

## 7. Crash Capture

The reference unit sets `LimitCORE=infinity`, but the host still needs normal
core-dump handling enabled. Typical commands:

```bash
coredumpctl list
coredumpctl info <PID>
```

If your distro routes core dumps elsewhere, keep the same base unit and use the
platform-native crash collector.

## 8. Rolling Reload

`propane` supports rolling reload via `HUP`, and the reference unit maps:

```bash
sudo systemctl reload arlen@myapp
```

That is the preferred config-only or release-only refresh path when you do not
need a hard restart.
