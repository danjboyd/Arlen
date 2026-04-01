SHELL := /bin/bash
.RECIPEPREFIX = >

ROOT_DIR := $(CURDIR)
GNUSTEP_RESOLVER := $(ROOT_DIR)/tools/resolve_gnustep.sh
GNUSTEP_SH ?= $(shell bash "$(GNUSTEP_RESOLVER)" 2>/dev/null || true)
BUILD_DIR := $(ROOT_DIR)/build
OBJ_DIR := $(BUILD_DIR)/obj
LIB_DIR := $(BUILD_DIR)/lib
GEN_DIR := $(BUILD_DIR)/gen/templates
MODULE_GEN_DIR := $(BUILD_DIR)/gen/module_templates
MODULE_GEN_MANIFEST_DIR := $(MODULE_GEN_DIR)/manifests
TECH_DEMO_GEN_DIR := $(BUILD_DIR)/gen/tech_demo_templates

EOC_TOOL := $(BUILD_DIR)/eocc
SMOKE_RENDER_TOOL := $(BUILD_DIR)/eoc-smoke-render
BOOMHAUER_TOOL := $(BUILD_DIR)/boomhauer
TECH_DEMO_SERVER_TOOL := $(BUILD_DIR)/tech-demo-server
API_REFERENCE_SERVER_TOOL := $(BUILD_DIR)/api-reference-server
AUTH_PRIMITIVES_SERVER_TOOL := $(BUILD_DIR)/auth-primitives-server
MIGRATION_SAMPLE_SERVER_TOOL := $(BUILD_DIR)/migration-sample-server
ARLEN_DATA_EXAMPLE_TOOL := $(BUILD_DIR)/arlen-data-example
ARLEN_TOOL := $(BUILD_DIR)/arlen
JSON_PERF_BENCH_TOOL := $(BUILD_DIR)/json-perf-bench
DISPATCH_PERF_BENCH_TOOL := $(BUILD_DIR)/dispatch-perf-bench
HTTP_PARSE_PERF_BENCH_TOOL := $(BUILD_DIR)/http-parse-perf-bench
ROUTE_MATCH_PERF_BENCH_TOOL := $(BUILD_DIR)/route-match-perf-bench
BACKEND_CONTRACT_MATRIX_TOOL := $(BUILD_DIR)/backend-contract-matrix
PHASE23_LIVE_SMOKE_TOOL := $(BUILD_DIR)/phase23-dataverse-live-smoke
ARLEN_FRAMEWORK_LIB := $(LIB_DIR)/libArlenFramework.a

TEMPLATE_ROOT := $(ROOT_DIR)/templates
TEMPLATE_FILES := $(shell find $(TEMPLATE_ROOT) -type f -name '*.html.eoc' 2>/dev/null | sort)
ROOT_TEMPLATE_DIRS := $(shell if [ -d $(TEMPLATE_ROOT) ]; then find $(TEMPLATE_ROOT) -type d | sort; fi)
TECH_DEMO_ROOT := $(ROOT_DIR)/examples/tech_demo
TECH_DEMO_TEMPLATE_ROOT := $(TECH_DEMO_ROOT)/templates
TECH_DEMO_TEMPLATE_FILES := $(shell find $(TECH_DEMO_TEMPLATE_ROOT) -type f -name '*.html.eoc' 2>/dev/null | sort)
TECH_DEMO_TEMPLATE_DIRS := $(shell if [ -d $(TECH_DEMO_TEMPLATE_ROOT) ]; then find $(TECH_DEMO_TEMPLATE_ROOT) -type d | sort; fi)
MODULE_TEMPLATE_FILES := $(shell find modules -type f -path '*/Resources/Templates/*.html.eoc' 2>/dev/null | sort)
MODULE_TEMPLATE_DIRS := $(shell if [ -d modules ]; then find modules -type d | sort; fi)

FRAMEWORK_OBJC_SRCS := $(shell find src -type f -name '*.m' | sort)
MODULE_SRCS := $(shell find modules -type f -path '*/Sources/*.m' 2>/dev/null | sort)
ARLEN_ENABLE_YYJSON ?= 1
ARLEN_ENABLE_LLHTTP ?= 1
ARLEN_XCTEST ?= xctest
ARLEN_XCTEST_LD_LIBRARY_PATH ?=
TEST ?=
SKIP_TEST ?=
ifneq ($(filter $(ARLEN_ENABLE_YYJSON),0 1),$(ARLEN_ENABLE_YYJSON))
$(error ARLEN_ENABLE_YYJSON must be 0 or 1)
endif
ifneq ($(filter $(ARLEN_ENABLE_LLHTTP),0 1),$(ARLEN_ENABLE_LLHTTP))
$(error ARLEN_ENABLE_LLHTTP must be 0 or 1)
endif
ifeq ($(ARLEN_ENABLE_YYJSON),1)
YYJSON_C_SRCS := src/Arlen/Support/third_party/yyjson/yyjson.c
else
YYJSON_C_SRCS :=
endif
ifeq ($(ARLEN_ENABLE_LLHTTP),1)
LLHTTP_C_SRCS := src/Arlen/Support/third_party/llhttp/llhttp.c src/Arlen/Support/third_party/llhttp/api.c src/Arlen/Support/third_party/llhttp/http.c
else
LLHTTP_C_SRCS :=
endif
ARGON2_C_SRCS := src/Arlen/Support/third_party/argon2/src/argon2.c src/Arlen/Support/third_party/argon2/src/core.c src/Arlen/Support/third_party/argon2/src/encoding.c src/Arlen/Support/third_party/argon2/src/ref.c src/Arlen/Support/third_party/argon2/src/blake2/blake2b.c
FRAMEWORK_C_SRCS := $(YYJSON_C_SRCS) $(LLHTTP_C_SRCS) $(ARGON2_C_SRCS)
FRAMEWORK_SRCS := $(FRAMEWORK_OBJC_SRCS) $(FRAMEWORK_C_SRCS)
ARLEN_DATA_SRCS := $(shell find src/Arlen/Data -type f -name '*.m' | sort)
JSON_SERIALIZATION_SRCS := src/Arlen/Support/ALNJSONSerialization.m $(YYJSON_C_SRCS)
EOC_RUNTIME_SRCS := src/Arlen/MVC/Template/ALNEOCRuntime.m src/Arlen/MVC/Template/ALNEOCTranspiler.m

UNIT_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenUnitTests.xctest
UNIT_TEST_BIN := $(UNIT_TEST_BUNDLE)/ArlenUnitTests
UNIT_TEST_TARGET_NAME := $(notdir $(basename $(UNIT_TEST_BUNDLE)))
INTEGRATION_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenIntegrationTests.xctest
INTEGRATION_TEST_BIN := $(INTEGRATION_TEST_BUNDLE)/ArlenIntegrationTests
INTEGRATION_TEST_TARGET_NAME := $(notdir $(basename $(INTEGRATION_TEST_BUNDLE)))
BROWSER_ERROR_AUDIT_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenBrowserErrorAudit.xctest
BROWSER_ERROR_AUDIT_TEST_BIN := $(BROWSER_ERROR_AUDIT_TEST_BUNDLE)/ArlenBrowserErrorAudit
PHASE20_SQL_BUILDER_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase20SQLBuilderTests.xctest
PHASE20_SQL_BUILDER_TEST_BIN := $(PHASE20_SQL_BUILDER_TEST_BUNDLE)/ArlenPhase20SQLBuilderTests
PHASE20_SCHEMA_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase20SchemaTests.xctest
PHASE20_SCHEMA_TEST_BIN := $(PHASE20_SCHEMA_TEST_BUNDLE)/ArlenPhase20SchemaTests
PHASE20_POSTGRES_LIVE_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase20PostgresLiveTests.xctest
PHASE20_POSTGRES_LIVE_TEST_BIN := $(PHASE20_POSTGRES_LIVE_TEST_BUNDLE)/ArlenPhase20PostgresLiveTests
PHASE20_MSSQL_LIVE_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase20MSSQLLiveTests.xctest
PHASE20_MSSQL_LIVE_TEST_BIN := $(PHASE20_MSSQL_LIVE_TEST_BUNDLE)/ArlenPhase20MSSQLLiveTests
PHASE20_ROUTING_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase20RoutingTests.xctest
PHASE20_ROUTING_TEST_BIN := $(PHASE20_ROUTING_TEST_BUNDLE)/ArlenPhase20RoutingTests
PHASE21_TEMPLATE_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase21TemplateTests.xctest
PHASE21_TEMPLATE_TEST_BIN := $(PHASE21_TEMPLATE_TEST_BUNDLE)/ArlenPhase21TemplateTests
PHASE23_DATAVERSE_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase23DataverseTests.xctest
PHASE23_DATAVERSE_TEST_BIN := $(PHASE23_DATAVERSE_TEST_BUNDLE)/ArlenPhase23DataverseTests
PHASE26_ORM_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase26ORMTests.xctest
PHASE26_ORM_TEST_BIN := $(PHASE26_ORM_TEST_BUNDLE)/ArlenPhase26ORMTests
GNUSTEP_TEST_HOME := $(ROOT_DIR)/.gnustep-home

UNIT_TEST_SRCS := $(shell find tests/unit -type f -name '*.m' | sort)
INTEGRATION_TEST_SRCS := $(shell find tests/integration -type f -name '*.m' | sort)
BROWSER_ERROR_AUDIT_SRCS := $(shell find tests/browser_error_audit -type f -name '*.m' | sort)
TEST_SHARED_SRCS := $(shell find tests/shared -type f -name '*.m' 2>/dev/null | sort)
PHASE20_SQL_BUILDER_TEST_SRCS := tests/phase20/Phase20SQLBuilderFocusedTests.m
PHASE20_SCHEMA_TEST_SRCS := tests/phase20/Phase20SchemaFocusedTests.m
PHASE20_POSTGRES_LIVE_TEST_SRCS := tests/phase20/Phase20PostgresLiveFocusedTests.m
PHASE20_MSSQL_LIVE_TEST_SRCS := tests/phase20/Phase20MSSQLLiveFocusedTests.m
PHASE20_ROUTING_TEST_SRCS := tests/phase20/Phase20RoutingPoolFocusedTests.m
PHASE21_TEMPLATE_TEST_SRCS := tests/unit/TemplateParserTests.m tests/unit/TemplateCodegenTests.m tests/unit/TemplateSecurityTests.m tests/unit/TemplateRegressionTests.m
PHASE23_DATAVERSE_TEST_SRCS := tests/unit/DataverseRuntimeTests.m tests/unit/DataverseQueryTests.m tests/unit/DataverseReadTests.m tests/unit/DataverseWriteTests.m tests/unit/DataverseMetadataTests.m tests/unit/DataverseRegressionTests.m tests/unit/DataverseArtifactTests.m
PHASE26_ORM_TEST_SRCS := tests/unit/ORMCodegenTests.m tests/unit/ORMRuntimeTests.m

FRAMEWORK_MODULE_INCLUDE_FLAGS := $(addprefix -I,$(shell find modules -mindepth 2 -maxdepth 2 -type d -name 'Sources' 2>/dev/null | sort))
INCLUDE_FLAGS := -Isrc -Isrc/Arlen -Isrc/Arlen/Core -Isrc/Arlen/Data -Isrc/Arlen/HTTP -Isrc/Arlen/MVC/Controller -Isrc/Arlen/MVC/Middleware -Isrc/Arlen/MVC/Routing -Isrc/Arlen/MVC/Template -Isrc/Arlen/MVC/View -Isrc/Arlen/Support -Isrc/Arlen/Support/third_party/argon2/include -Isrc/Arlen/Support/third_party/argon2/src -Isrc/MojoObjc -Isrc/MojoObjc/Core -Isrc/MojoObjc/Data -Isrc/MojoObjc/HTTP -Isrc/MojoObjc/MVC/Controller -Isrc/MojoObjc/MVC/Middleware -Isrc/MojoObjc/MVC/Routing -Isrc/MojoObjc/MVC/Template -Isrc/MojoObjc/MVC/View -Isrc/MojoObjc/Support $(FRAMEWORK_MODULE_INCLUDE_FLAGS) -I/usr/include/postgresql
EXTRA_OBJC_FLAGS ?=
ARC_REQUIRED_FLAG := -fobjc-arc
PIC_FLAG := -fPIC
FEATURE_FLAGS := -DARLEN_ENABLE_YYJSON=$(ARLEN_ENABLE_YYJSON) -DARLEN_ENABLE_LLHTTP=$(ARLEN_ENABLE_LLHTTP)
THIRD_PARTY_FEATURE_FLAGS := -DARGON2_NO_THREADS=1
COMMON_COMPILE_FLAGS := $(FEATURE_FLAGS) $(THIRD_PARTY_FEATURE_FLAGS) $(PIC_FLAG) $(EXTRA_OBJC_FLAGS)
BUILD_FLAGS_SENTINEL_INPUT := GNUSTEP_SH=$(GNUSTEP_SH)|ARC_REQUIRED_FLAG=$(ARC_REQUIRED_FLAG)|PIC_FLAG=$(PIC_FLAG)|FEATURE_FLAGS=$(FEATURE_FLAGS)|THIRD_PARTY_FEATURE_FLAGS=$(THIRD_PARTY_FEATURE_FLAGS)|EXTRA_OBJC_FLAGS=$(EXTRA_OBJC_FLAGS)
BUILD_FLAGS_SENTINEL_HASH := $(shell printf '%s\n' '$(BUILD_FLAGS_SENTINEL_INPUT)' | sha256sum | awk '{print $$1}')
BUILD_FLAGS_SENTINEL := $(BUILD_DIR)/.build-flags.$(BUILD_FLAGS_SENTINEL_HASH)
ifneq ($(findstring -fno-objc-arc,$(EXTRA_OBJC_FLAGS)),)
$(error EXTRA_OBJC_FLAGS cannot contain -fno-objc-arc; Arlen enforces ARC across all first-party Objective-C compile paths)
endif
override OBJC_FLAGS := $$(gnustep-config --objc-flags) $(ARC_REQUIRED_FLAG) $(COMMON_COMPILE_FLAGS)
override C_COMPILE_FLAGS := $$(gnustep-config --objc-flags) $(COMMON_COMPILE_FLAGS)
ifneq ($(findstring $(ARC_REQUIRED_FLAG),$(OBJC_FLAGS)),$(ARC_REQUIRED_FLAG))
$(error OBJC_FLAGS must include -fobjc-arc)
endif
ifneq ($(findstring -fno-objc-arc,$(OBJC_FLAGS)),)
$(error OBJC_FLAGS cannot disable ARC)
endif
BASE_LINK_LIBS := $$(gnustep-config --base-libs) -ldl -lcrypto -ldispatch
XCTEST_LINK_LIBS := $(BASE_LINK_LIBS) -lXCTest

ROOT_TEMPLATE_MANIFEST := $(GEN_DIR)/manifest.json
ROOT_TRANSPILE_STATE := $(GEN_DIR)/.transpile.state
MODULE_TRANSPILE_STATE := $(MODULE_GEN_DIR)/.transpile.state
TECH_DEMO_TRANSPILE_STATE := $(TECH_DEMO_GEN_DIR)/.transpile.state
TECH_DEMO_TEMPLATE_MANIFEST := $(TECH_DEMO_GEN_DIR)/manifest.json

define obj_path
$(OBJ_DIR)/$(patsubst %.m,%.o,$(patsubst %.c,%.o,$(patsubst $(ROOT_DIR)/%,%,$(1))))
endef

define objs_from
$(foreach src,$(1),$(call obj_path,$(src)))
endef

define repo_relative_path
$(patsubst $(ROOT_DIR)/%,%,$(1))
endef

define module_generated_source_for
$(shell path='$(1)'; \
  module_id="$${path#modules/}"; \
  module_id="$${module_id%%/*}"; \
  relative_path="$${path#modules/$$module_id/Resources/Templates/}"; \
  printf '%s/modules/%s/%s.m\n' "$(MODULE_GEN_DIR)" "$$module_id" "$$relative_path")
endef

define root_generated_source_for
$(patsubst $(TEMPLATE_ROOT)/%.html.eoc,$(GEN_DIR)/%.html.eoc.m,$(1))
endef

define tech_demo_generated_source_for
$(patsubst $(TECH_DEMO_TEMPLATE_ROOT)/%.html.eoc,$(TECH_DEMO_GEN_DIR)/%.html.eoc.m,$(1))
endef

define root_generated_object_for
$(call obj_path,$(call root_generated_source_for,$(1)))
endef

define tech_demo_generated_object_for
$(call obj_path,$(call tech_demo_generated_source_for,$(1)))
endef

define xctest_filter_args
$(if $(strip $(TEST)),-only-testing:$(1)/$(strip $(TEST))) $(if $(strip $(SKIP_TEST)),-skip-testing:$(1)/$(strip $(SKIP_TEST)))
endef

define xctest_runtime_env
LD_PRELOAD="$(XCTEST_LD_PRELOAD)" $(if $(strip $(ARLEN_XCTEST_LD_LIBRARY_PATH)),LD_LIBRARY_PATH="$(ARLEN_XCTEST_LD_LIBRARY_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" )ASAN_OPTIONS="$(ASAN_OPTIONS)" UBSAN_OPTIONS="$(UBSAN_OPTIONS)"
endef

define root_generated_source_rel_for
$(call repo_relative_path,$(call root_generated_source_for,$(1)))
endef

define tech_demo_generated_source_rel_for
$(call repo_relative_path,$(call tech_demo_generated_source_for,$(1)))
endef

define module_generated_object_for
$(call obj_path,$(call module_generated_source_for,$(1)))
endef

define module_generated_source_rel_for
$(call repo_relative_path,$(call module_generated_source_for,$(1)))
endef

ROOT_GENERATED_SRCS := $(patsubst $(TEMPLATE_ROOT)/%.html.eoc,$(GEN_DIR)/%.html.eoc.m,$(TEMPLATE_FILES))
TECH_DEMO_GENERATED_SRCS := $(patsubst $(TECH_DEMO_TEMPLATE_ROOT)/%.html.eoc,$(TECH_DEMO_GEN_DIR)/%.html.eoc.m,$(TECH_DEMO_TEMPLATE_FILES))
MODULE_GENERATED_SRCS := $(shell if [ -d modules ]; then \
  find modules -type f -path '*/Resources/Templates/*.html.eoc' | sort | \
  while IFS= read -r path; do \
    module_id="$${path#modules/}"; \
    module_id="$${module_id%%/*}"; \
    relative_path="$${path#modules/$$module_id/Resources/Templates/}"; \
    printf '%s/modules/%s/%s.m\n' "$(MODULE_GEN_DIR)" "$$module_id" "$$relative_path"; \
  done; \
fi)

FRAMEWORK_OBJS := $(call objs_from,$(FRAMEWORK_SRCS))
MODULE_OBJS := $(call objs_from,$(MODULE_SRCS))
ROOT_GENERATED_OBJS := $(call objs_from,$(ROOT_GENERATED_SRCS))
TECH_DEMO_GENERATED_OBJS := $(call objs_from,$(TECH_DEMO_GENERATED_SRCS))
MODULE_GENERATED_OBJS := $(call objs_from,$(MODULE_GENERATED_SRCS))

EOCC_ENTRY_OBJS := $(call objs_from,tools/eocc.m)
EOC_RUNTIME_OBJS := $(call objs_from,$(EOC_RUNTIME_SRCS))
ARLEN_ENTRY_OBJS := $(call objs_from,tools/arlen.m)
BOOMHAUER_ENTRY_OBJS := $(call objs_from,tools/boomhauer.m)
SMOKE_RENDER_ENTRY_OBJS := $(call objs_from,tools/eoc_smoke_render.m)
TECH_DEMO_SERVER_ENTRY_OBJS := $(call objs_from,examples/tech_demo/src/tech_demo_server.m)
API_REFERENCE_SERVER_ENTRY_OBJS := $(call objs_from,examples/api_reference/src/api_reference_server.m)
AUTH_PRIMITIVES_SERVER_ENTRY_OBJS := $(call objs_from,examples/auth_primitives/src/auth_primitives_server.m)
MIGRATION_SAMPLE_SERVER_ENTRY_OBJS := $(call objs_from,examples/gsweb_migration/src/migration_sample_server.m)
ARLEN_DATA_EXAMPLE_ENTRY_OBJS := $(call objs_from,examples/arlen_data/src/arlen_data_example.m)
JSON_PERF_BENCH_ENTRY_OBJS := $(call objs_from,tools/json_perf_bench.m)
DISPATCH_PERF_BENCH_ENTRY_OBJS := $(call objs_from,tools/dispatch_perf_bench.m)
HTTP_PARSE_PERF_BENCH_ENTRY_OBJS := $(call objs_from,tools/http_parse_perf_bench.m)
ROUTE_MATCH_PERF_BENCH_ENTRY_OBJS := $(call objs_from,tools/route_match_perf_bench.m)
BACKEND_CONTRACT_MATRIX_ENTRY_OBJS := $(call objs_from,tools/backend_contract_matrix.m)
PHASE23_LIVE_SMOKE_ENTRY_OBJS := $(call objs_from,tools/phase23_dataverse_live_smoke.m)
UNIT_TEST_OBJS := $(call objs_from,$(UNIT_TEST_SRCS))
INTEGRATION_TEST_OBJS := $(call objs_from,$(INTEGRATION_TEST_SRCS))
BROWSER_ERROR_AUDIT_TEST_OBJS := $(call objs_from,$(BROWSER_ERROR_AUDIT_SRCS))
TEST_SHARED_OBJS := $(call objs_from,$(TEST_SHARED_SRCS))
PHASE20_SQL_BUILDER_TEST_OBJS := $(call objs_from,$(PHASE20_SQL_BUILDER_TEST_SRCS))
PHASE20_SCHEMA_TEST_OBJS := $(call objs_from,$(PHASE20_SCHEMA_TEST_SRCS))
PHASE20_POSTGRES_LIVE_TEST_OBJS := $(call objs_from,$(PHASE20_POSTGRES_LIVE_TEST_SRCS))
PHASE20_MSSQL_LIVE_TEST_OBJS := $(call objs_from,$(PHASE20_MSSQL_LIVE_TEST_SRCS))
PHASE20_ROUTING_TEST_OBJS := $(call objs_from,$(PHASE20_ROUTING_TEST_SRCS))
PHASE21_TEMPLATE_TEST_OBJS := $(call objs_from,$(PHASE21_TEMPLATE_TEST_SRCS))
PHASE23_DATAVERSE_TEST_OBJS := $(call objs_from,$(PHASE23_DATAVERSE_TEST_SRCS))
PHASE26_ORM_TEST_OBJS := $(call objs_from,$(PHASE26_ORM_TEST_SRCS))

ALL_OBJECTS := $(sort $(FRAMEWORK_OBJS) $(MODULE_OBJS) $(ROOT_GENERATED_OBJS) $(TECH_DEMO_GENERATED_OBJS) $(MODULE_GENERATED_OBJS) $(EOCC_ENTRY_OBJS) $(ARLEN_ENTRY_OBJS) $(BOOMHAUER_ENTRY_OBJS) $(SMOKE_RENDER_ENTRY_OBJS) $(TECH_DEMO_SERVER_ENTRY_OBJS) $(API_REFERENCE_SERVER_ENTRY_OBJS) $(AUTH_PRIMITIVES_SERVER_ENTRY_OBJS) $(MIGRATION_SAMPLE_SERVER_ENTRY_OBJS) $(ARLEN_DATA_EXAMPLE_ENTRY_OBJS) $(JSON_PERF_BENCH_ENTRY_OBJS) $(DISPATCH_PERF_BENCH_ENTRY_OBJS) $(HTTP_PARSE_PERF_BENCH_ENTRY_OBJS) $(ROUTE_MATCH_PERF_BENCH_ENTRY_OBJS) $(BACKEND_CONTRACT_MATRIX_ENTRY_OBJS) $(PHASE23_LIVE_SMOKE_ENTRY_OBJS) $(UNIT_TEST_OBJS) $(INTEGRATION_TEST_OBJS) $(BROWSER_ERROR_AUDIT_TEST_OBJS) $(TEST_SHARED_OBJS) $(PHASE20_SQL_BUILDER_TEST_OBJS) $(PHASE20_SCHEMA_TEST_OBJS) $(PHASE20_POSTGRES_LIVE_TEST_OBJS) $(PHASE20_MSSQL_LIVE_TEST_OBJS) $(PHASE20_ROUTING_TEST_OBJS) $(PHASE21_TEMPLATE_TEST_OBJS) $(PHASE23_DATAVERSE_TEST_OBJS) $(PHASE26_ORM_TEST_OBJS))
ALL_DEPFILES := $(ALL_OBJECTS:.o=.d)

.PHONY: all framework-artifacts eocc transpile module-transpile tech-demo-transpile generated-compile arlen boomhauer tech-demo-server api-reference-server auth-primitives-server migration-sample-server arlen-data-example json-perf-bench dispatch-perf-bench http-parse-perf-bench route-match-perf-bench backend-contract-matrix phase23-live-smoke test-data-layer dev-server tech-demo smoke-render smoke routes build-tests test test-unit test-unit-filter test-integration test-integration-filter browser-error-audit phase20-sql-builder-tests phase20-schema-tests phase20-postgres-live-tests phase20-mssql-live-tests phase20-routing-tests phase20-focused phase21-template-tests phase21-protocol-tests phase21-generated-app-tests phase21-focused phase21-confidence phase23-dataverse-tests phase23-focused phase23-confidence phase26-orm-tests perf perf-fast ci-perf-smoke parity-phaseb perf-phasec perf-phased deploy-smoke phase5e-confidence phase12-confidence phase13-confidence phase14-confidence phase15-confidence phase16-confidence phase19-confidence phase20-confidence ci-quality ci-sanitizers ci-fault-injection ci-release-certification ci-json-abstraction ci-json-perf ci-dispatch-perf ci-http-parse-perf ci-route-match-perf ci-backend-parity-matrix ci-protocol-adversarial ci-syscall-faults ci-allocation-faults ci-soak ci-chaos-restart ci-static-analysis ci-blob-throughput ci-phase11-protocol-adversarial ci-phase11-fuzz ci-phase11-live-adversarial ci-phase11-sanitizers ci-phase11 ci-docs ci-benchmark-contracts check docs-api docs-html docs-serve clean

all: eocc transpile generated-compile arlen boomhauer

$(BUILD_DIR):
>mkdir -p $(BUILD_DIR)

$(BUILD_FLAGS_SENTINEL): | $(BUILD_DIR)
>@rm -f $(BUILD_DIR)/.build-flags.*
>@touch $@

$(OBJ_DIR):
>mkdir -p $(OBJ_DIR)

$(LIB_DIR):
>mkdir -p $(LIB_DIR)

$(GEN_DIR):
>mkdir -p $(GEN_DIR)

$(MODULE_GEN_DIR):
>mkdir -p $(MODULE_GEN_DIR)

$(MODULE_GEN_MANIFEST_DIR):
>mkdir -p $(MODULE_GEN_MANIFEST_DIR)

$(TECH_DEMO_GEN_DIR):
>mkdir -p $(TECH_DEMO_GEN_DIR)

$(ROOT_TRANSPILE_STATE): $(EOC_TOOL) $(TEMPLATE_FILES) $(ROOT_TEMPLATE_DIRS) | $(GEN_DIR)
>@if [ -n "$(strip $(TEMPLATE_FILES))" ]; then \
>  $(EOC_TOOL) --template-root $(TEMPLATE_ROOT) --output-dir $(GEN_DIR) --manifest $(ROOT_TEMPLATE_MANIFEST) $(TEMPLATE_FILES); \
>else \
>  find $(GEN_DIR) -mindepth 1 -maxdepth 1 ! -name '.transpile.state' -exec rm -rf {} + 2>/dev/null || true; \
>fi
>@touch $@

$(MODULE_TRANSPILE_STATE): $(EOC_TOOL) $(MODULE_TEMPLATE_FILES) $(MODULE_TEMPLATE_DIRS) | $(MODULE_GEN_DIR) $(MODULE_GEN_MANIFEST_DIR)
>@mkdir -p $(MODULE_GEN_DIR)/modules
>@if [ -d $(MODULE_GEN_DIR)/modules ]; then \
>  while IFS= read -r existing_dir; do \
>    module_id="$$(basename "$$existing_dir")"; \
>    if [ ! -d "modules/$$module_id" ]; then \
>      rm -rf "$$existing_dir" "$(MODULE_GEN_MANIFEST_DIR)/$$module_id.json"; \
>    fi; \
>  done < <(find $(MODULE_GEN_DIR)/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort); \
>fi
>@if [ -d modules ]; then \
>  while IFS= read -r module_root; do \
>    module_id="$$(basename "$$module_root")"; \
>    module_template_root="$$module_root/Resources/Templates"; \
>    if [ ! -d "$$module_template_root" ]; then \
>      rm -rf "$(MODULE_GEN_DIR)/modules/$$module_id" "$(MODULE_GEN_MANIFEST_DIR)/$$module_id.json"; \
>      continue; \
>    fi; \
>    mapfile -t module_template_files < <(find "$$module_template_root" -type f -name '*.html.eoc' | sort); \
>    if [ $${#module_template_files[@]} -eq 0 ]; then \
>      rm -rf "$(MODULE_GEN_DIR)/modules/$$module_id" "$(MODULE_GEN_MANIFEST_DIR)/$$module_id.json"; \
>      continue; \
>    fi; \
>    $(EOC_TOOL) --template-root "$$module_template_root" --output-dir "$(MODULE_GEN_DIR)" --manifest "$(MODULE_GEN_MANIFEST_DIR)/$$module_id.json" --logical-prefix "modules/$$module_id" "$${module_template_files[@]}"; \
>  done < <(find modules -mindepth 1 -maxdepth 1 -type d | sort); \
>fi
>@touch $@

$(TECH_DEMO_TRANSPILE_STATE): $(EOC_TOOL) $(TECH_DEMO_TEMPLATE_FILES) $(TECH_DEMO_TEMPLATE_DIRS) | $(TECH_DEMO_GEN_DIR)
>@if [ -n "$(strip $(TECH_DEMO_TEMPLATE_FILES))" ]; then \
>  $(EOC_TOOL) --template-root $(TECH_DEMO_TEMPLATE_ROOT) --output-dir $(TECH_DEMO_GEN_DIR) --manifest $(TECH_DEMO_TEMPLATE_MANIFEST) $(TECH_DEMO_TEMPLATE_FILES); \
>else \
>  find $(TECH_DEMO_GEN_DIR) -mindepth 1 -maxdepth 1 ! -name '.transpile.state' -exec rm -rf {} + 2>/dev/null || true; \
>fi
>@touch $@

$(GEN_DIR)/%.html.eoc.m: $(TEMPLATE_ROOT)/%.html.eoc | $(ROOT_TRANSPILE_STATE)
>@test -f $@

$(TECH_DEMO_GEN_DIR)/%.html.eoc.m: $(TECH_DEMO_TEMPLATE_ROOT)/%.html.eoc | $(TECH_DEMO_TRANSPILE_STATE)
>@test -f $@

define module_generated_rule
$(call module_generated_source_for,$(1)): $(1) | $(MODULE_TRANSPILE_STATE)
>@test -f $$@
endef

$(foreach module_template,$(MODULE_TEMPLATE_FILES),$(eval $(call module_generated_rule,$(module_template))))

define root_generated_object_rule
$(call root_generated_object_for,$(1)): $(BUILD_FLAGS_SENTINEL) $(call root_generated_source_for,$(1)) $(1)
>@mkdir -p $$(@D)
>@source $$(GNUSTEP_SH) && clang $$(OBJC_FLAGS) $$(INCLUDE_FLAGS) -MMD -MP -MF $$(@:.o=.d) -c $(call root_generated_source_rel_for,$(1)) -o $$@
endef

define tech_demo_generated_object_rule
$(call tech_demo_generated_object_for,$(1)): $(BUILD_FLAGS_SENTINEL) $(call tech_demo_generated_source_for,$(1)) $(1)
>@mkdir -p $$(@D)
>@source $$(GNUSTEP_SH) && clang $$(OBJC_FLAGS) $$(INCLUDE_FLAGS) -MMD -MP -MF $$(@:.o=.d) -c $(call tech_demo_generated_source_rel_for,$(1)) -o $$@
endef

define module_generated_object_rule
$(call module_generated_object_for,$(1)): $(BUILD_FLAGS_SENTINEL) $(call module_generated_source_for,$(1)) $(1)
>@mkdir -p $$(@D)
>@source $$(GNUSTEP_SH) && clang $$(OBJC_FLAGS) $$(INCLUDE_FLAGS) -MMD -MP -MF $$(@:.o=.d) -c $(call module_generated_source_rel_for,$(1)) -o $$@
endef

$(foreach root_template,$(TEMPLATE_FILES),$(eval $(call root_generated_object_rule,$(root_template))))
$(foreach tech_demo_template,$(TECH_DEMO_TEMPLATE_FILES),$(eval $(call tech_demo_generated_object_rule,$(tech_demo_template))))
$(foreach module_template,$(MODULE_TEMPLATE_FILES),$(eval $(call module_generated_object_rule,$(module_template))))

$(OBJ_DIR)/%.o: %.m $(BUILD_FLAGS_SENTINEL)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(OBJ_DIR)/%.o: %.c $(BUILD_FLAGS_SENTINEL)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(C_COMPILE_FLAGS) $(INCLUDE_FLAGS) -MMD -MP -MF $(@:.o=.d) -c $< -o $@

$(ARLEN_FRAMEWORK_LIB): $(FRAMEWORK_OBJS) | $(LIB_DIR)
>@rm -f $@
>@ar rcs $@ $(FRAMEWORK_OBJS)

framework-artifacts: eocc $(ARLEN_FRAMEWORK_LIB)

$(EOC_TOOL): $(EOCC_ENTRY_OBJS) $(EOC_RUNTIME_OBJS) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(EOCC_ENTRY_OBJS) $(EOC_RUNTIME_OBJS) -o $(EOC_TOOL) $(BASE_LINK_LIBS)

eocc: $(EOC_TOOL)

transpile: $(ROOT_TRANSPILE_STATE)

module-transpile: $(MODULE_TRANSPILE_STATE)

tech-demo-transpile: $(TECH_DEMO_TRANSPILE_STATE)

generated-compile: $(ROOT_TRANSPILE_STATE) $(ROOT_GENERATED_OBJS)

$(ARLEN_TOOL): $(ARLEN_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(ARLEN_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(ARLEN_TOOL) $(BASE_LINK_LIBS)

arlen: $(ARLEN_TOOL)

$(JSON_PERF_BENCH_TOOL): $(JSON_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(JSON_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(JSON_PERF_BENCH_TOOL) $(BASE_LINK_LIBS)

json-perf-bench: $(JSON_PERF_BENCH_TOOL)

$(DISPATCH_PERF_BENCH_TOOL): $(DISPATCH_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(DISPATCH_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(DISPATCH_PERF_BENCH_TOOL) $(BASE_LINK_LIBS)

dispatch-perf-bench: $(DISPATCH_PERF_BENCH_TOOL)

$(HTTP_PARSE_PERF_BENCH_TOOL): $(HTTP_PARSE_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(HTTP_PARSE_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(HTTP_PARSE_PERF_BENCH_TOOL) $(BASE_LINK_LIBS)

http-parse-perf-bench: $(HTTP_PARSE_PERF_BENCH_TOOL)

$(ROUTE_MATCH_PERF_BENCH_TOOL): $(ROUTE_MATCH_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(ROUTE_MATCH_PERF_BENCH_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(ROUTE_MATCH_PERF_BENCH_TOOL) $(BASE_LINK_LIBS)

route-match-perf-bench: $(ROUTE_MATCH_PERF_BENCH_TOOL)

$(BACKEND_CONTRACT_MATRIX_TOOL): $(BACKEND_CONTRACT_MATRIX_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(BACKEND_CONTRACT_MATRIX_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(BACKEND_CONTRACT_MATRIX_TOOL) $(BASE_LINK_LIBS)

backend-contract-matrix: $(BACKEND_CONTRACT_MATRIX_TOOL)

$(PHASE23_LIVE_SMOKE_TOOL): $(PHASE23_LIVE_SMOKE_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE23_LIVE_SMOKE_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(PHASE23_LIVE_SMOKE_TOOL) $(BASE_LINK_LIBS)

$(BOOMHAUER_TOOL): $(BOOMHAUER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(ROOT_GENERATED_OBJS) | $(BUILD_DIR) $(ROOT_TRANSPILE_STATE)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(BOOMHAUER_ENTRY_OBJS) $(ROOT_GENERATED_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(BOOMHAUER_TOOL) $(BASE_LINK_LIBS)

boomhauer: $(BOOMHAUER_TOOL)
dev-server: boomhauer

$(TECH_DEMO_SERVER_TOOL): $(TECH_DEMO_SERVER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) $(TECH_DEMO_GENERATED_OBJS) | $(BUILD_DIR) $(MODULE_TRANSPILE_STATE) $(TECH_DEMO_TRANSPILE_STATE)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(TECH_DEMO_SERVER_ENTRY_OBJS) $(MODULE_OBJS) $(TECH_DEMO_GENERATED_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(TECH_DEMO_SERVER_TOOL) $(BASE_LINK_LIBS)

tech-demo-server: $(TECH_DEMO_SERVER_TOOL)

$(API_REFERENCE_SERVER_TOOL): $(API_REFERENCE_SERVER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(API_REFERENCE_SERVER_ENTRY_OBJS) $(MODULE_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(API_REFERENCE_SERVER_TOOL) $(BASE_LINK_LIBS)

api-reference-server: $(API_REFERENCE_SERVER_TOOL)

$(AUTH_PRIMITIVES_SERVER_TOOL): $(AUTH_PRIMITIVES_SERVER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(AUTH_PRIMITIVES_SERVER_ENTRY_OBJS) $(MODULE_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(AUTH_PRIMITIVES_SERVER_TOOL) $(BASE_LINK_LIBS)

auth-primitives-server: $(AUTH_PRIMITIVES_SERVER_TOOL)

$(MIGRATION_SAMPLE_SERVER_TOOL): $(MIGRATION_SAMPLE_SERVER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(MIGRATION_SAMPLE_SERVER_ENTRY_OBJS) $(MODULE_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(MIGRATION_SAMPLE_SERVER_TOOL) $(BASE_LINK_LIBS)

migration-sample-server: $(MIGRATION_SAMPLE_SERVER_TOOL)

$(ARLEN_DATA_EXAMPLE_TOOL): $(ARLEN_DATA_EXAMPLE_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) | $(BUILD_DIR)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(ARLEN_DATA_EXAMPLE_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(ARLEN_DATA_EXAMPLE_TOOL) $(BASE_LINK_LIBS)

arlen-data-example: $(ARLEN_DATA_EXAMPLE_TOOL)

test-data-layer: arlen-data-example
>$(ARLEN_DATA_EXAMPLE_TOOL)

tech-demo: tech-demo-server
>TECH_DEMO_PORT="$${TECH_DEMO_PORT:-3110}" ./bin/tech-demo

$(SMOKE_RENDER_TOOL): $(SMOKE_RENDER_ENTRY_OBJS) $(ARLEN_FRAMEWORK_LIB) $(ROOT_GENERATED_OBJS) | $(BUILD_DIR) $(ROOT_TRANSPILE_STATE)
>@mkdir -p $(@D)
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(SMOKE_RENDER_ENTRY_OBJS) $(ROOT_GENERATED_OBJS) $(ARLEN_FRAMEWORK_LIB) -o $(SMOKE_RENDER_TOOL) $(BASE_LINK_LIBS)

smoke-render: $(SMOKE_RENDER_TOOL)

$(UNIT_TEST_BIN): $(UNIT_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) $(ROOT_GENERATED_OBJS) $(MODULE_GENERATED_OBJS) | $(ROOT_TRANSPILE_STATE) $(MODULE_TRANSPILE_STATE)
>@mkdir -p $(UNIT_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(UNIT_TEST_OBJS) $(TEST_SHARED_OBJS) $(MODULE_OBJS) $(ROOT_GENERATED_OBJS) $(MODULE_GENERATED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(UNIT_TEST_BIN) $(XCTEST_LINK_LIBS)
>@cp tests/Info-gnustep-unit.plist $(UNIT_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(INTEGRATION_TEST_BIN): $(INTEGRATION_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) $(MODULE_OBJS) $(ROOT_GENERATED_OBJS) $(MODULE_GENERATED_OBJS) $(BOOMHAUER_TOOL) $(TECH_DEMO_SERVER_TOOL) $(API_REFERENCE_SERVER_TOOL) $(AUTH_PRIMITIVES_SERVER_TOOL) $(MIGRATION_SAMPLE_SERVER_TOOL) | $(ROOT_TRANSPILE_STATE) $(MODULE_TRANSPILE_STATE)
>@mkdir -p $(INTEGRATION_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(INTEGRATION_TEST_OBJS) $(TEST_SHARED_OBJS) $(MODULE_OBJS) $(ROOT_GENERATED_OBJS) $(MODULE_GENERATED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(INTEGRATION_TEST_BIN) $(XCTEST_LINK_LIBS)
>@cp tests/Info-gnustep-integration.plist $(INTEGRATION_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(BROWSER_ERROR_AUDIT_TEST_BIN): $(BROWSER_ERROR_AUDIT_TEST_OBJS)
>@mkdir -p $(BROWSER_ERROR_AUDIT_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(BROWSER_ERROR_AUDIT_TEST_OBJS) -shared -fPIC -o $(BROWSER_ERROR_AUDIT_TEST_BIN) $(XCTEST_LINK_LIBS)
>@cp tests/Info-gnustep-browser-error-audit.plist $(BROWSER_ERROR_AUDIT_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE20_SQL_BUILDER_TEST_BIN): $(PHASE20_SQL_BUILDER_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE20_SQL_BUILDER_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE20_SQL_BUILDER_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE20_SQL_BUILDER_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase20SQLBuilderTests/g' tests/Info-gnustep-unit.plist > $(PHASE20_SQL_BUILDER_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE20_SCHEMA_TEST_BIN): $(PHASE20_SCHEMA_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE20_SCHEMA_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE20_SCHEMA_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE20_SCHEMA_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase20SchemaTests/g' tests/Info-gnustep-unit.plist > $(PHASE20_SCHEMA_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE20_POSTGRES_LIVE_TEST_BIN): $(PHASE20_POSTGRES_LIVE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE20_POSTGRES_LIVE_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE20_POSTGRES_LIVE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE20_POSTGRES_LIVE_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase20PostgresLiveTests/g' tests/Info-gnustep-unit.plist > $(PHASE20_POSTGRES_LIVE_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE20_MSSQL_LIVE_TEST_BIN): $(PHASE20_MSSQL_LIVE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE20_MSSQL_LIVE_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE20_MSSQL_LIVE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE20_MSSQL_LIVE_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase20MSSQLLiveTests/g' tests/Info-gnustep-unit.plist > $(PHASE20_MSSQL_LIVE_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE20_ROUTING_TEST_BIN): $(PHASE20_ROUTING_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE20_ROUTING_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE20_ROUTING_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE20_ROUTING_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase20RoutingTests/g' tests/Info-gnustep-unit.plist > $(PHASE20_ROUTING_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE21_TEMPLATE_TEST_BIN): $(PHASE21_TEMPLATE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE21_TEMPLATE_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE21_TEMPLATE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE21_TEMPLATE_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase21TemplateTests/g' tests/Info-gnustep-unit.plist > $(PHASE21_TEMPLATE_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE23_DATAVERSE_TEST_BIN): $(PHASE23_DATAVERSE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) $(ARLEN_TOOL)
>@mkdir -p $(PHASE23_DATAVERSE_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE23_DATAVERSE_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE23_DATAVERSE_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase23DataverseTests/g' tests/Info-gnustep-unit.plist > $(PHASE23_DATAVERSE_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(PHASE26_ORM_TEST_BIN): $(PHASE26_ORM_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB)
>@mkdir -p $(PHASE26_ORM_TEST_BUNDLE)/Resources
>@source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(PHASE26_ORM_TEST_OBJS) $(TEST_SHARED_OBJS) $(ARLEN_FRAMEWORK_LIB) -shared -fPIC -o $(PHASE26_ORM_TEST_BIN) $(XCTEST_LINK_LIBS)
>@sed 's/ArlenUnitTests/ArlenPhase26ORMTests/g' tests/Info-gnustep-unit.plist > $(PHASE26_ORM_TEST_BUNDLE)/Resources/Info-gnustep.plist

build-tests: $(UNIT_TEST_BIN) $(INTEGRATION_TEST_BIN)

test-unit: $(UNIT_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(UNIT_TEST_BUNDLE)

test-unit-filter: $(UNIT_TEST_BIN)
>if [ -z "$(strip $(TEST)$(SKIP_TEST))" ]; then echo "test-unit-filter: set TEST=TestClass[/testMethod] or SKIP_TEST=TestClass[/testMethod]" >&2; exit 2; fi
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(UNIT_TEST_BUNDLE) $(call xctest_filter_args,$(UNIT_TEST_TARGET_NAME))

test-integration: $(INTEGRATION_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(INTEGRATION_TEST_BUNDLE)

test-integration-filter: $(INTEGRATION_TEST_BIN)
>if [ -z "$(strip $(TEST)$(SKIP_TEST))" ]; then echo "test-integration-filter: set TEST=TestClass[/testMethod] or SKIP_TEST=TestClass[/testMethod]" >&2; exit 2; fi
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(INTEGRATION_TEST_BUNDLE) $(call xctest_filter_args,$(INTEGRATION_TEST_TARGET_NAME))

browser-error-audit: $(BROWSER_ERROR_AUDIT_TEST_BIN) boomhauer
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" ARLEN_BROWSER_ERROR_AUDIT_OUTPUT_DIR="$(ROOT_DIR)/build/browser-error-audit" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(BROWSER_ERROR_AUDIT_TEST_BUNDLE)
>@echo "browser-error-audit: open $(ROOT_DIR)/build/browser-error-audit/index.html"

phase20-sql-builder-tests: $(PHASE20_SQL_BUILDER_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE20_SQL_BUILDER_TEST_BUNDLE)

phase20-schema-tests: $(PHASE20_SCHEMA_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE20_SCHEMA_TEST_BUNDLE)

phase20-postgres-live-tests: $(PHASE20_POSTGRES_LIVE_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE20_POSTGRES_LIVE_TEST_BUNDLE)

phase20-mssql-live-tests: $(PHASE20_MSSQL_LIVE_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE20_MSSQL_LIVE_TEST_BUNDLE)

phase20-routing-tests: $(PHASE20_ROUTING_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE20_ROUTING_TEST_BUNDLE)

phase20-focused: phase20-sql-builder-tests phase20-schema-tests phase20-routing-tests phase20-postgres-live-tests phase20-mssql-live-tests

phase21-template-tests: $(PHASE21_TEMPLATE_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE21_TEMPLATE_TEST_BUNDLE)

phase21-protocol-tests:
>bash ./tools/ci/run_phase21_protocol_corpus.sh

phase21-generated-app-tests:
>bash ./tools/ci/run_phase21_generated_app_matrix.sh

phase21-focused: phase21-template-tests phase21-protocol-tests phase21-generated-app-tests

phase21-confidence:
>bash ./tools/ci/run_phase21_confidence.sh

phase23-dataverse-tests: $(PHASE23_DATAVERSE_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE23_DATAVERSE_TEST_BUNDLE)

phase23-live-smoke: $(PHASE23_LIVE_SMOKE_TOOL)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" ARLEN_PHASE23_LIVE_SMOKE_OUTPUT="$${ARLEN_PHASE23_LIVE_SMOKE_OUTPUT:-$(ROOT_DIR)/build/release_confidence/phase23/live_smoke/manifest.json}" && $(PHASE23_LIVE_SMOKE_TOOL)

phase23-focused: phase23-dataverse-tests

phase23-confidence:
>bash ./tools/ci/run_phase23_confidence.sh

phase26-orm-tests: $(PHASE26_ORM_TEST_BIN)
>mkdir -p $(GNUSTEP_TEST_HOME)/GNUstep/Defaults/.lck
>source $(GNUSTEP_SH) && export HOME="$(GNUSTEP_TEST_HOME)" GNUSTEP_USER_DIR="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_ROOT="$(GNUSTEP_TEST_HOME)/GNUstep" GNUSTEP_USER_DEFAULTS_DIR="$(GNUSTEP_TEST_HOME)/GNUstep/Defaults" && $(xctest_runtime_env) "$(ARLEN_XCTEST)" $(PHASE26_ORM_TEST_BUNDLE)

test: test-unit test-integration

routes: boomhauer
>./build/boomhauer --print-routes

perf: boomhauer
>bash ./tests/performance/run_perf.sh

perf-fast: boomhauer
>ARLEN_PERF_FAST=1 bash ./tests/performance/run_perf.sh

ci-perf-smoke:
>bash ./tools/ci/run_perf_smoke.sh

parity-phaseb: boomhauer
>bash ./tests/performance/run_phaseb_parity.sh

perf-phasec: boomhauer
>python3 ./tests/performance/run_phasec_protocol.py

perf-phased: boomhauer
>python3 ./tests/performance/run_phased_campaign.py

deploy-smoke:
>bash ./tools/deploy/smoke_release.sh --app-root examples/tech_demo --framework-root $(ROOT_DIR)

phase5e-confidence:
>python3 ./tools/ci/generate_phase5e_confidence_artifacts.py --repo-root $(ROOT_DIR) --output-dir $(ROOT_DIR)/build/release_confidence/phase5e

phase12-confidence:
>bash ./tools/ci/run_phase12_confidence.sh

phase13-confidence:
>bash ./tools/ci/run_phase13_confidence.sh

phase14-confidence:
>bash ./tools/ci/run_phase14_confidence.sh

phase15-confidence:
>bash ./tools/ci/run_phase15_confidence.sh

phase16-confidence:
>bash ./tools/ci/run_phase16_confidence.sh

phase19-confidence:
>bash ./tools/ci/run_phase19_confidence.sh

phase20-confidence:
>bash ./tools/ci/run_phase20_confidence.sh

ci-quality:
>bash ./tools/ci/run_phase5e_quality.sh

ci-sanitizers:
>bash ./tools/ci/run_phase10m_sanitizer_matrix.sh

ci-fault-injection:
>bash ./tools/ci/run_phase9i_fault_injection.sh

ci-release-certification:
>bash ./tools/ci/run_phase9j_release_certification.sh

ci-json-abstraction:
>python3 ./tools/ci/check_runtime_json_abstraction.py --repo-root $(ROOT_DIR)

ci-json-perf:
>bash ./tools/ci/run_phase10e_json_performance.sh

ci-dispatch-perf:
>bash ./tools/ci/run_phase10g_dispatch_performance.sh

ci-http-parse-perf:
>bash ./tools/ci/run_phase10h_http_parse_performance.sh

ci-route-match-perf:
>bash ./tools/ci/run_phase10l_route_match_investigation.sh

ci-backend-parity-matrix:
>bash ./tools/ci/run_phase10m_backend_parity_matrix.sh

ci-protocol-adversarial:
>bash ./tools/ci/run_phase10m_protocol_adversarial.sh

ci-syscall-faults:
>bash ./tools/ci/run_phase10m_syscall_fault_injection.sh

ci-allocation-faults:
>bash ./tools/ci/run_phase10m_allocation_fault_injection.sh

ci-soak:
>bash ./tools/ci/run_phase10m_soak.sh

ci-chaos-restart:
>bash ./tools/ci/run_phase10m_chaos_restart.sh

ci-static-analysis:
>bash ./tools/ci/run_phase10m_static_analysis.sh

ci-blob-throughput:
>bash ./tools/ci/run_phase10m_blob_throughput.sh

ci-phase11-protocol-adversarial:
>bash ./tools/ci/run_phase11_protocol_adversarial.sh

ci-phase11-fuzz:
>bash ./tools/ci/run_phase11_protocol_fuzz.sh

ci-phase11-live-adversarial:
>bash ./tools/ci/run_phase11_live_adversarial.sh

ci-phase11-sanitizers:
>bash ./tools/ci/run_phase11_sanitizer_matrix.sh

ci-phase11:
>bash ./tools/ci/run_phase11_confidence.sh

ci-docs:
>bash ./tools/ci/run_docs_quality.sh

ci-benchmark-contracts:
>python3 ./tools/ci/check_benchmark_contracts.py --repo-root "$(ROOT_DIR)"

check: ci-json-abstraction test-unit test-integration perf

docs-html:
>bash ./tools/build_docs_html.sh

docs-api:
>python3 ./tools/docs/generate_api_reference.py --repo-root $(ROOT_DIR)

docs-serve: docs-html
>DOCS_PORT="$${DOCS_PORT:-4173}" python3 -m http.server "$${DOCS_PORT}" --directory $(ROOT_DIR)/build/docs

smoke: smoke-render boomhauer
>bash ./bin/smoke

clean:
>rm -rf $(BUILD_DIR) $(ROOT_DIR)/.gnustep $(ROOT_DIR)/.gnustep-home

-include $(wildcard $(ALL_DEPFILES))
