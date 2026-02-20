SHELL := /bin/bash
.RECIPEPREFIX = >

ROOT_DIR := $(CURDIR)
GNUSTEP_SH := /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
BUILD_DIR := $(ROOT_DIR)/build
GEN_DIR := $(BUILD_DIR)/gen/templates
TECH_DEMO_GEN_DIR := $(BUILD_DIR)/gen/tech_demo_templates

EOC_TOOL := $(BUILD_DIR)/eocc
SMOKE_RENDER_TOOL := $(BUILD_DIR)/eoc-smoke-render
BOOMHAUER_TOOL := $(BUILD_DIR)/boomhauer
TECH_DEMO_SERVER_TOOL := $(BUILD_DIR)/tech-demo-server
API_REFERENCE_SERVER_TOOL := $(BUILD_DIR)/api-reference-server
MIGRATION_SAMPLE_SERVER_TOOL := $(BUILD_DIR)/migration-sample-server
ARLEN_DATA_EXAMPLE_TOOL := $(BUILD_DIR)/arlen-data-example
ARLEN_TOOL := $(BUILD_DIR)/arlen

TEMPLATE_ROOT := $(ROOT_DIR)/templates
TEMPLATE_FILES := $(shell find $(TEMPLATE_ROOT) -type f -name '*.html.eoc' | sort)
GENERATED_TEMPLATE_SRCS := $(shell find $(GEN_DIR) -type f -name '*.m' 2>/dev/null | sort)
TECH_DEMO_ROOT := $(ROOT_DIR)/examples/tech_demo
TECH_DEMO_TEMPLATE_ROOT := $(TECH_DEMO_ROOT)/templates
TECH_DEMO_TEMPLATE_FILES := $(shell find $(TECH_DEMO_TEMPLATE_ROOT) -type f -name '*.html.eoc' | sort)

FRAMEWORK_SRCS := $(shell find src -type f -name '*.m' | sort)
ARLEN_DATA_SRCS := $(shell find src/Arlen/Data -type f -name '*.m' | sort)
EOC_RUNTIME_SRCS := src/Arlen/MVC/Template/ALNEOCRuntime.m src/Arlen/MVC/Template/ALNEOCTranspiler.m

UNIT_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenUnitTests.xctest
UNIT_TEST_BIN := $(UNIT_TEST_BUNDLE)/ArlenUnitTests
INTEGRATION_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenIntegrationTests.xctest
INTEGRATION_TEST_BIN := $(INTEGRATION_TEST_BUNDLE)/ArlenIntegrationTests

UNIT_TEST_SRCS := $(shell find tests/unit -type f -name '*.m' | sort)
INTEGRATION_TEST_SRCS := $(shell find tests/integration -type f -name '*.m' | sort)

INCLUDE_FLAGS := -Isrc/Arlen -Isrc/Arlen/Core -Isrc/Arlen/Data -Isrc/Arlen/HTTP -Isrc/Arlen/MVC/Controller -Isrc/Arlen/MVC/Middleware -Isrc/Arlen/MVC/Routing -Isrc/Arlen/MVC/Template -Isrc/Arlen/MVC/View -Isrc/Arlen/Support -Isrc/MojoObjc -Isrc/MojoObjc/Core -Isrc/MojoObjc/Data -Isrc/MojoObjc/HTTP -Isrc/MojoObjc/MVC/Controller -Isrc/MojoObjc/MVC/Middleware -Isrc/MojoObjc/MVC/Routing -Isrc/MojoObjc/MVC/Template -Isrc/MojoObjc/MVC/View -Isrc/MojoObjc/Support -I/usr/include/postgresql
OBJC_FLAGS := $$(gnustep-config --objc-flags) -fobjc-arc

.PHONY: all eocc transpile tech-demo-transpile generated-compile arlen boomhauer tech-demo-server api-reference-server migration-sample-server arlen-data-example test-data-layer dev-server tech-demo smoke-render smoke routes build-tests test test-unit test-integration perf perf-fast deploy-smoke ci-quality check docs-html clean

all: eocc transpile generated-compile arlen boomhauer

$(BUILD_DIR):
>mkdir -p $(BUILD_DIR)

$(EOC_TOOL): tools/eocc.m $(EOC_RUNTIME_SRCS) | $(BUILD_DIR)
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) tools/eocc.m $(EOC_RUNTIME_SRCS) -o $(EOC_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

eocc: $(EOC_TOOL)

transpile: eocc
>mkdir -p $(GEN_DIR)
>$(EOC_TOOL) --template-root $(TEMPLATE_ROOT) --output-dir $(GEN_DIR) $(TEMPLATE_FILES)

tech-demo-transpile: eocc
>mkdir -p $(TECH_DEMO_GEN_DIR)
>$(EOC_TOOL) --template-root $(TECH_DEMO_TEMPLATE_ROOT) --output-dir $(TECH_DEMO_GEN_DIR) $(TECH_DEMO_TEMPLATE_FILES)

generated-compile: transpile
>source $(GNUSTEP_SH) && generated_files="$$(find $(GEN_DIR) -type f -name '*.m' | sort)"; \
>if [ -z "$$generated_files" ]; then \
>  echo "No generated template sources found in $(GEN_DIR)"; \
>  exit 1; \
>fi; \
>clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $$generated_files $(FRAMEWORK_SRCS) -shared -fPIC -o $(BUILD_DIR)/libArlenFramework.so $$(gnustep-config --base-libs) -ldl -lcrypto

$(ARLEN_TOOL): tools/arlen.m src/Arlen/Core/ALNConfig.m src/Arlen/Data/ALNMigrationRunner.m src/Arlen/Data/ALNPg.m src/Arlen/Data/ALNSchemaCodegen.m | $(BUILD_DIR)
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) tools/arlen.m src/Arlen/Core/ALNConfig.m src/Arlen/Data/ALNMigrationRunner.m src/Arlen/Data/ALNPg.m src/Arlen/Data/ALNSchemaCodegen.m -o $(ARLEN_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

arlen: $(ARLEN_TOOL)

$(BOOMHAUER_TOOL): tools/boomhauer.m transpile
>source $(GNUSTEP_SH) && generated_files="$$(find $(GEN_DIR) -type f -name '*.m' | sort)"; \
>if [ -z "$$generated_files" ]; then \
>  echo "No generated template sources found in $(GEN_DIR)"; \
>  exit 1; \
>fi; \
>clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) tools/boomhauer.m $(FRAMEWORK_SRCS) $$generated_files -o $(BOOMHAUER_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

boomhauer: $(BOOMHAUER_TOOL)
dev-server: boomhauer

$(TECH_DEMO_SERVER_TOOL): examples/tech_demo/src/tech_demo_server.m tech-demo-transpile
>source $(GNUSTEP_SH) && generated_files="$$(find $(TECH_DEMO_GEN_DIR) -type f -name '*.m' | sort)"; \
>if [ -z "$$generated_files" ]; then \
>  echo "No generated template sources found in $(TECH_DEMO_GEN_DIR)"; \
>  exit 1; \
>fi; \
>clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) examples/tech_demo/src/tech_demo_server.m $(FRAMEWORK_SRCS) $$generated_files -o $(TECH_DEMO_SERVER_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

tech-demo-server: $(TECH_DEMO_SERVER_TOOL)

$(API_REFERENCE_SERVER_TOOL): examples/api_reference/src/api_reference_server.m
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) examples/api_reference/src/api_reference_server.m $(FRAMEWORK_SRCS) -o $(API_REFERENCE_SERVER_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

api-reference-server: $(API_REFERENCE_SERVER_TOOL)

$(MIGRATION_SAMPLE_SERVER_TOOL): examples/gsweb_migration/src/migration_sample_server.m
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) examples/gsweb_migration/src/migration_sample_server.m $(FRAMEWORK_SRCS) -o $(MIGRATION_SAMPLE_SERVER_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

migration-sample-server: $(MIGRATION_SAMPLE_SERVER_TOOL)

$(ARLEN_DATA_EXAMPLE_TOOL): examples/arlen_data/src/arlen_data_example.m
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) -Isrc examples/arlen_data/src/arlen_data_example.m $(ARLEN_DATA_SRCS) -o $(ARLEN_DATA_EXAMPLE_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

arlen-data-example: $(ARLEN_DATA_EXAMPLE_TOOL)

test-data-layer: arlen-data-example
>$(ARLEN_DATA_EXAMPLE_TOOL)

tech-demo: tech-demo-server
>TECH_DEMO_PORT="$${TECH_DEMO_PORT:-3110}" ./bin/tech-demo

$(SMOKE_RENDER_TOOL): tools/eoc_smoke_render.m transpile
>source $(GNUSTEP_SH) && generated_files="$$(find $(GEN_DIR) -type f -name '*.m' | sort)"; \
>if [ -z "$$generated_files" ]; then \
>  echo "No generated template sources found in $(GEN_DIR)"; \
>  exit 1; \
>fi; \
>clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) tools/eoc_smoke_render.m src/Arlen/MVC/Template/ALNEOCRuntime.m $$generated_files -o $(SMOKE_RENDER_TOOL) $$(gnustep-config --base-libs) -ldl -lcrypto

smoke-render: $(SMOKE_RENDER_TOOL)

$(UNIT_TEST_BIN): $(UNIT_TEST_SRCS) $(FRAMEWORK_SRCS) transpile
>mkdir -p $(UNIT_TEST_BUNDLE)/Resources
>source $(GNUSTEP_SH) && generated_files="$$(find $(GEN_DIR) -type f -name '*.m' | sort)"; \
>clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(UNIT_TEST_SRCS) $(FRAMEWORK_SRCS) $$generated_files -shared -fPIC -o $(UNIT_TEST_BIN) $$(gnustep-config --base-libs) -ldl -lcrypto -lXCTest
>cp tests/Info-gnustep-unit.plist $(UNIT_TEST_BUNDLE)/Resources/Info-gnustep.plist

$(INTEGRATION_TEST_BIN): $(INTEGRATION_TEST_SRCS) boomhauer tech-demo-server api-reference-server migration-sample-server
>mkdir -p $(INTEGRATION_TEST_BUNDLE)/Resources
>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) $(INTEGRATION_TEST_SRCS) -shared -fPIC -o $(INTEGRATION_TEST_BIN) $$(gnustep-config --base-libs) -ldl -lcrypto -lXCTest
>cp tests/Info-gnustep-integration.plist $(INTEGRATION_TEST_BUNDLE)/Resources/Info-gnustep.plist

build-tests: $(UNIT_TEST_BIN) $(INTEGRATION_TEST_BIN)

test-unit: $(UNIT_TEST_BIN)
>mkdir -p $(ROOT_DIR)/.gnustep
>export GNUSTEP_USER_ROOT="$(ROOT_DIR)/.gnustep"; source $(GNUSTEP_SH) && xctest $(UNIT_TEST_BUNDLE)

test-integration: $(INTEGRATION_TEST_BIN)
>mkdir -p $(ROOT_DIR)/.gnustep
>export GNUSTEP_USER_ROOT="$(ROOT_DIR)/.gnustep"; source $(GNUSTEP_SH) && xctest $(INTEGRATION_TEST_BUNDLE)

test: test-unit test-integration

routes: boomhauer
>./build/boomhauer --print-routes

perf: boomhauer
>bash ./tests/performance/run_perf.sh

perf-fast: boomhauer
>ARLEN_PERF_FAST=1 bash ./tests/performance/run_perf.sh

deploy-smoke:
>bash ./tools/deploy/smoke_release.sh --app-root examples/tech_demo --framework-root $(ROOT_DIR)

ci-quality:
>bash ./tools/ci/run_phase3c_quality.sh

check: test-unit test-integration perf


docs-html:
>bash ./tools/build_docs_html.sh

smoke: smoke-render boomhauer
>bash ./bin/smoke

clean:
>rm -rf $(BUILD_DIR) $(ROOT_DIR)/.gnustep
