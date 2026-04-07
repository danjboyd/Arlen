#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${ARLEN_PHASE29_OUTPUT_DIR:-$repo_root/build/release_confidence/phase29}"

mkdir -p "$output_dir"

source "$repo_root/tools/source_gnustep_env.sh"

make -C "$repo_root" arlen >/dev/null
make -C "$repo_root" build-tests >/dev/null

cli_app_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase29-cli-XXXXXX")"
ops_app_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase29-ops-XXXXXX")"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/arlen-phase29-work-XXXXXX")"
trap 'rm -rf "$cli_app_root" "$ops_app_root" "$work_root"' EXIT

mkdir -p "$cli_app_root/config/environments" "$cli_app_root/db/migrations"
cat >"$cli_app_root/config/app.plist" <<'EOF'
{
  host = "127.0.0.1";
  port = 3000;
  database = {
    connectionString = "postgresql:///phase29_confidence";
    adapter = "postgresql";
  };
}
EOF
cat >"$cli_app_root/config/environments/production.plist" <<'EOF'
{
  logFormat = "json";
}
EOF
cat >"$cli_app_root/app_lite.m" <<'EOF'
#import <Foundation/Foundation.h>
int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }
EOF
cat >"$cli_app_root/db/migrations/202604071400_create_phase29.sql" <<'EOF'
CREATE TABLE phase29_confidence (id INTEGER);
EOF

cli_log="$work_root/phase29_runtime.log"
printf 'line-a\nline-b\nline-c\n' >"$cli_log"
cli_releases="$work_root/releases"

push_a_json="$output_dir/deploy_push_a.json"
push_b_json="$output_dir/deploy_push_b.json"
release_json="$output_dir/deploy_release.json"
status_json="$output_dir/deploy_status.json"
doctor_json="$output_dir/deploy_doctor.json"
rollback_json="$output_dir/deploy_rollback.json"
logs_json="$output_dir/deploy_logs.json"

(
  cd "$cli_app_root"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy push \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --release-id rel-a \
    --allow-missing-certification \
    --json >"$push_a_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy push \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --release-id rel-b \
    --allow-missing-certification \
    --json >"$push_b_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy release \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --release-id rel-b \
    --allow-missing-certification \
    --skip-migrate \
    --json >"$release_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy status \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --json >"$status_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy doctor \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --json >"$doctor_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy rollback \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --runtime-action none \
    --json >"$rollback_json"
  ARLEN_FRAMEWORK_ROOT="$repo_root" "$repo_root/build/arlen" deploy logs \
    --app-root "$cli_app_root" \
    --releases-dir "$cli_releases" \
    --file "$cli_log" \
    --lines 2 \
    --json >"$logs_json"
)

reserved_releases="$work_root/reserved-releases"
mkdir -p "$ops_app_root/config/environments"
cat >"$ops_app_root/config/app.plist" <<'EOF'
{
  host = "127.0.0.1";
  port = 3000;
  logFormat = "text";
}
EOF
cat >"$ops_app_root/config/environments/development.plist" <<'EOF'
{
  logFormat = "text";
}
EOF
cat >"$ops_app_root/app_lite.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import "ALNContext.h"
#import "ALNController.h"
#import "ArlenServer.h"

@interface Phase29ReservedController : ALNController
@end

@implementation Phase29ReservedController
- (id)token:(ALNContext *)ctx {
  NSString *token = [ctx.params[@"token"] isKindOfClass:[NSString class]] ? ctx.params[@"token"] : @"";
  [self renderText:[NSString stringWithFormat:@"token:%@\n", token]];
  return nil;
}
@end

static ALNApplication *CreateApp(NSString *environment, NSString *appRootCurrent) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment configRoot:appRootCurrent error:&error];
  if (app == nil) {
    fprintf(stderr, "failed loading config: %s\n", [[error localizedDescription] UTF8String]);
    return nil;
  }
  [app registerRouteMethod:@"GET"
                      path:@"/:token"
                      name:@"token"
           controllerClass:[Phase29ReservedController class]
                    action:@"token"];
  return app;
}

static void PrintUsage(void) {
  fprintf(stdout, "Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    int portOverride = 0;
    NSString *host = nil;
    NSString *environment = @"development";
    BOOL once = NO;
    BOOL printRoutes = NO;
    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--port"]) {
        if ((idx + 1) >= argc) { PrintUsage(); return 2; }
        portOverride = atoi(argv[++idx]);
      } else if ([arg isEqualToString:@"--host"]) {
        if ((idx + 1) >= argc) { PrintUsage(); return 2; }
        host = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--env"]) {
        if ((idx + 1) >= argc) { PrintUsage(); return 2; }
        environment = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--once"]) {
        once = YES;
      } else if ([arg isEqualToString:@"--print-routes"]) {
        printRoutes = YES;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
        return 2;
      }
    }
    NSString *appRootCurrent = [[[NSProcessInfo processInfo] environment] objectForKey:@"ARLEN_APP_ROOT"];
    if ([appRootCurrent length] == 0) {
      appRootCurrent = [[NSFileManager defaultManager] currentDirectoryPath];
    }
    ALNApplication *app = CreateApp(environment, appRootCurrent);
    if (app == nil) {
      return 1;
    }
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app
                                                            publicRoot:[appRootCurrent stringByAppendingPathComponent:@"public"]];
    server.serverName = @"boomhauer";
    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }
    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
EOF

reserved_prepare_log="$output_dir/reserved_prepare.log"
reserved_health_txt="$output_dir/reserved_health.txt"
reserved_ready_txt="$output_dir/reserved_ready.txt"
reserved_metrics_txt="$output_dir/reserved_metrics.txt"
reserved_shadow_txt="$output_dir/reserved_shadow.txt"

ARLEN_FRAMEWORK_ROOT="$repo_root" ARLEN_APP_ROOT="$ops_app_root" \
  "$repo_root/bin/boomhauer" --prepare-only >"$reserved_prepare_log" 2>&1
reserved_binary="$ops_app_root/.boomhauer/build/boomhauer-app"
port="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
ARLEN_FRAMEWORK_ROOT="$repo_root" ARLEN_APP_ROOT="$ops_app_root" \
  "$reserved_binary" --port "$port" >"$output_dir/reserved_server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" >/dev/null 2>&1 || true; rm -rf "$cli_app_root" "$ops_app_root" "$work_root"' EXIT
python3 - "$port" <<'PY'
import sys
import time
import urllib.request

port = int(sys.argv[1])
url = f"http://127.0.0.1:{port}/healthz"
for _ in range(40):
    try:
        urllib.request.urlopen(url, timeout=1).read()
        break
    except Exception:
        time.sleep(0.1)
else:
    raise SystemExit("reserved endpoint server failed to become ready")
PY
curl -fsS "http://127.0.0.1:$port/healthz" >"$reserved_health_txt"
curl -fsS "http://127.0.0.1:$port/readyz" >"$reserved_ready_txt"
curl -fsS "http://127.0.0.1:$port/metrics" >"$reserved_metrics_txt"
curl -fsS "http://127.0.0.1:$port/shadowed" >"$reserved_shadow_txt"
kill "$server_pid" >/dev/null 2>&1 || true
wait "$server_pid"
trap 'rm -rf "$cli_app_root" "$ops_app_root" "$work_root"' EXIT

python3 "$repo_root/tools/ci/generate_phase29_confidence_artifacts.py" \
  --output-dir "$output_dir" \
  --deploy-push-a "$push_a_json" \
  --deploy-push-b "$push_b_json" \
  --deploy-release "$release_json" \
  --deploy-status "$status_json" \
  --deploy-doctor "$doctor_json" \
  --deploy-rollback "$rollback_json" \
  --deploy-logs "$logs_json" \
  --reserved-prepare-log "$reserved_prepare_log" \
  --reserved-health "$reserved_health_txt" \
  --reserved-ready "$reserved_ready_txt" \
  --reserved-metrics "$reserved_metrics_txt" \
  --reserved-shadow "$reserved_shadow_txt"

echo "ci: phase29 confidence gate complete"
