# cli-only.mk — fork F4: CLI-only shippable binary (CBM_FORK_CLI_ONLY).
#
# Included from Makefile.cbm (one `include` line). Purely additive: nothing here
# is a prerequisite of `cbm`, `cbm-with-ui`, `test`, or any default target, and
# $(PROD_SRCS) is untouched.
#
# Source set: PROD_SRCS minus the daemon runtime/frontend TUs. Retained from
# src/daemon: bootstrap.c (argv role classifier), project_lock.c (mutation
# serialization) and ipc.c (cbm_daemon_ipc_private_lock_directory_new, the one
# helper project_lock needs). Their unreferenced socket/coordination code is
# removed at link time by section GC (plan T4.3 option 1, zero src/daemon
# edits). verify-cli-only-link is the arbiter.
#
# Guarded edge TUs (compiled with -DCBM_FORK_CLI_ONLY=1 into separate
# objects): src/main.c, src/cli/cli.c, src/mcp/mcp.c (fences the JSON-RPC
# router/stdio transport) and src/ui/http_server.c (fences /rpc). The guard
# only fences declarations and function bodies — no struct layout changes —
# so mixing guarded and unguarded objects is ABI-safe.
#
# E8: CFLAGS_PROD with the test-seam define filtered out — never seams.

CLI_ONLY_BIN = $(BUILD_DIR)/codebase-memory-cli
CLI_ONLY_DROPPED_DAEMON_SRCS = \
    src/daemon/daemon.c \
    src/daemon/version_cohort.c \
    src/daemon/runtime.c \
    src/daemon/application.c \
    src/daemon/frontend.c \
    src/daemon/host.c
CLI_ONLY_GUARDED_SRCS = src/cli/cli.c src/mcp/mcp.c src/ui/http_server.c
CLI_ONLY_REST_SRCS = $(filter-out $(CLI_ONLY_GUARDED_SRCS) $(CLI_ONLY_DROPPED_DAEMON_SRCS),$(PROD_SRCS)) \
    $(EXTRACTION_SRCS) $(AC_LZ4_SRCS) $(ZSTD_SRCS) $(SQLITE_WRITER_SRC)
CLI_ONLY_MAIN_OBJ = $(BUILD_DIR)/cli_only_main.o
CLI_ONLY_CLI_OBJ = $(BUILD_DIR)/cli_only_cli.o
CLI_ONLY_MCP_OBJ = $(BUILD_DIR)/cli_only_mcp.o
CLI_ONLY_HTTP_OBJ = $(BUILD_DIR)/cli_only_http_server.o
CLI_ONLY_SECTION_CFLAGS = -ffunction-sections -fdata-sections
ifeq ($(shell uname -s),Darwin)
CLI_ONLY_GC_LDFLAGS = -Wl,-dead_strip
else
CLI_ONLY_GC_LDFLAGS = -Wl,--gc-sections
endif
CLI_ONLY_CFLAGS = $(filter-out -DCBM_ENABLE_TEST_SEAMS=1,$(CFLAGS_PROD)) $(CLI_ONLY_SECTION_CFLAGS)
# D-3 (ARCH-7): only src/main.c needs relaxed unused diagnostics. Its guarded
# daemon/hook/worker/MCP role paths leave these upstream statics unreferenced
# (verified by removing the flags: cli.c, mcp.c and http_server.c build clean
# with -Werror; main.c fails with exactly this list):
#   -Wunused-variable: g_daemon_client
#   -Wunused-function: client_start_parent_watchdog, main_build_identity_status_name,
#     main_hook_report_absent_daemon, main_hook_report_conflicted_daemon,
#     main_local_command_cancel, main_local_maintenance_context_init,
#     main_local_maintenance_finish, main_local_transition_acquire,
#     main_local_transition_close, main_report_client_bootstrap_failure,
#     main_run_daemon_ctl, main_run_hook_frontend, main_version_cohort_close,
#     parse_ui_flags, setup_signal_handlers, worker_containment_unavailable,
#     worker_prepare_process_group, worker_start_parent_watchdog
# Wrapping those ~19 upstream helpers in #ifndef would enlarge the main.c
# upstream diff, so the relaxation stays per-TU instead.
CLI_ONLY_MAIN_CFLAGS = $(CLI_ONLY_CFLAGS) -Wno-unused-function -Wno-unused-variable

.PHONY: cbm-cli verify-cli-only-link

cbm-cli: $(OBJS_VENDORED_PROD) $(PROJECT_HDRS) | $(BUILD_DIR)
	@echo "=== cbm-cli: compiling guarded edge TUs with -DCBM_FORK_CLI_ONLY=1 ==="
	$(CC) $(CLI_ONLY_MAIN_CFLAGS) -DCBM_FORK_CLI_ONLY=1 -c -o $(CLI_ONLY_MAIN_OBJ) src/main.c
	$(CC) $(CLI_ONLY_CFLAGS) -DCBM_FORK_CLI_ONLY=1 -c -o $(CLI_ONLY_CLI_OBJ) src/cli/cli.c
	$(CC) $(CLI_ONLY_CFLAGS) -DCBM_FORK_CLI_ONLY=1 -c -o $(CLI_ONLY_MCP_OBJ) src/mcp/mcp.c
	$(CC) $(CLI_ONLY_CFLAGS) -DCBM_FORK_CLI_ONLY=1 -c -o $(CLI_ONLY_HTTP_OBJ) src/ui/http_server.c
	@echo "=== linking $(CLI_ONLY_BIN) (daemon runtime/frontend dropped, section GC) ==="
	$(CC) $(CLI_ONLY_CFLAGS) -o $(CLI_ONLY_BIN) \
		$(CLI_ONLY_MAIN_OBJ) $(CLI_ONLY_CLI_OBJ) $(CLI_ONLY_MCP_OBJ) $(CLI_ONLY_HTTP_OBJ) \
		$(CLI_ONLY_REST_SRCS) \
		$(OBJS_VENDORED_PROD) \
		$(LDFLAGS) $(CLI_ONLY_GC_LDFLAGS)
	@rm -f $(CLI_ONLY_MAIN_OBJ) $(CLI_ONLY_CLI_OBJ) $(CLI_ONLY_MCP_OBJ) $(CLI_ONLY_HTTP_OBJ)
	@echo "Built: $(CLI_ONLY_BIN)"

# F4 link-isolation gate (E2, E8). Verification-only; not in default/prod.
# Asserts on the linked binary: (a) no dropped daemon runtime/frontend symbols,
# (b) no ipc.c daemon-socket/coordination entry points, (c) no *test_seam*
# symbols; and that the engine, project_lock and classifier are present. The
# loopback UI listener (src/ui) is the only permitted socket user, so libc
# socket imports are not asserted here (F6 audits the UI).
CLI_ONLY_FORBIDDEN_PREFIXES = cbm_daemon_runtime_ cbm_daemon_frontend_ cbm_daemon_host_ \
    cbm_daemon_application_ cbm_daemon_service_ cbm_version_cohort_ \
    cbm_daemon_maintenance_monitor_ cbm_daemon_ipc_listen cbm_daemon_ipc_accept \
    cbm_daemon_ipc_connect cbm_daemon_ipc_startup_lock_ cbm_daemon_ipc_local_transition_ \
    cbm_daemon_ipc_lifetime_reservation_ cbm_mcp_server_run \
    cbm_mcp_server_handle cbm_jsonrpc_
# Protocol-string gate (ARCH-8). "initialize" is deliberately absent: it
# matches innocent text ("uninitialized"); protocolVersion + the symbol check
# cover it.
CLI_ONLY_FORBIDDEN_STRINGS = jsonrpc tools/list protocolVersion notifications/initialized
CLI_ONLY_STRS = $(BUILD_DIR)/cli_only_strings.txt
CLI_ONLY_REQUIRED_SYMS = cbm_mcp_handle_tool cbm_project_lock_manager_new cbm_daemon_process_role
CLI_ONLY_SYMS = $(BUILD_DIR)/cli_only_syms.txt

verify-cli-only-link: cbm-cli
	@echo "=== verify-cli-only-link: nm $(CLI_ONLY_BIN) ==="
	@nm "$(CLI_ONLY_BIN)" | awk '$$2 ~ /^[TtDdBbSs]$$/ {sub(/^_/, "", $$3); print $$3}' > $(CLI_ONLY_SYMS)
	@fail=0; \
	for p in $(CLI_ONLY_FORBIDDEN_PREFIXES); do \
		hits=$$(grep -E "^$$p" $(CLI_ONLY_SYMS) | head -5); \
		if [ -n "$$hits" ]; then echo "  FAIL: forbidden '$$p*' linked:"; echo "$$hits" | sed 's/^/      /'; fail=1; \
		else echo "  ok absent: $$p*"; fi; \
	done; \
	seams=$$(grep -i "test_seam" $(CLI_ONLY_SYMS) | head -5); \
	if [ -n "$$seams" ]; then echo "  FAIL: test seam symbols linked:"; echo "$$seams"; fail=1; \
	else echo "  ok absent: *test_seam*"; fi; \
	for sym in $(CLI_ONLY_REQUIRED_SYMS); do \
		if grep -qx "$$sym" $(CLI_ONLY_SYMS); then echo "  ok present: $$sym"; \
		else echo "  FAIL: required symbol missing: $$sym"; fail=1; fi; \
	done; \
	rm -f $(CLI_ONLY_SYMS); \
	strings -a "$(CLI_ONLY_BIN)" > $(CLI_ONLY_STRS); \
	for t in $(CLI_ONLY_FORBIDDEN_STRINGS); do \
		hits=$$(grep -F -- "$$t" $(CLI_ONLY_STRS) | head -5); \
		if [ -n "$$hits" ]; then echo "  FAIL: forbidden string '$$t' present:"; echo "$$hits" | cut -c1-160 | sed 's/^/      /'; fail=1; \
		else echo "  ok absent string: $$t"; fi; \
	done; \
	rm -f $(CLI_ONLY_STRS); \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@# Entry-dispatch smoke (E3/E4): non-CLI roles print help, exit 2, never answer JSON-RPC.
	@fail=0; \
	for argv in "" "--cbm-daemon-internal" "daemon status"; do \
		out=$$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | "$(CLI_ONLY_BIN)" $$argv 2>&1); rc=$$?; \
		if [ $$rc -eq 2 ] && ! echo "$$out" | grep -q '"jsonrpc"'; then echo "  ok inert: '$$argv' (rc=2)"; \
		else echo "  FAIL: '$$argv' rc=$$rc or JSON-RPC reply"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo "verify-cli-only-link: PASS"


# ── Milestone 01: smoke test for the shipped CLI (test-only, additive) ───────
.PHONY: test-cli-only

# test_cli_only_install.sh seeds genuine upstream entries with the default
# build's own writer, hence the $(BUILD_DIR)/codebase-memory-mcp prerequisite.
test-cli-only: cbm-cli $(BUILD_DIR)/codebase-memory-mcp
	CBM_TEST_BINARY="$(CURDIR)/$(CLI_ONLY_BIN)" bash tests/test_cli_only_smoke.sh
	CBM_TEST_BINARY="$(CURDIR)/$(CLI_ONLY_BIN)" CBM_UPSTREAM_BINARY="$(CURDIR)/$(BUILD_DIR)/codebase-memory-mcp" \
		bash tests/test_cli_only_install.sh

# ── Milestone 02: guarded HTTP test runner (test-only, additive) ─────────────
# Builds the ordinary test runner with src/ui/http_server.c and
# tests/test_httpd.c compiled with -DCBM_FORK_CLI_ONLY=1 into a separate
# directory (never mixed into $(BUILD_DIR)/test-runner) and runs only the
# httpd suite. src/mcp/mcp.c stays unguarded HERE ONLY: test_main.c links
# every suite and test_mcp.c drives the JSON-RPC router; the fork binary's
# guarded mcp.c is covered by verify-cli-only-link. Vendored test objects are
# reused from $(BUILD_DIR). Test seams come from CFLAGS_TEST exactly as for
# the default runner; this target is not a prerequisite of cbm-cli.
CLI_ONLY_UI_TEST_DIR = $(BUILD_DIR)-cli-only-test
CLI_ONLY_UI_TEST_RUNNER = $(CLI_ONLY_UI_TEST_DIR)/test-runner
CLI_ONLY_UI_GUARDED_SRCS = src/ui/http_server.c tests/test_httpd.c
CLI_ONLY_UI_GUARDED_OBJS = $(CLI_ONLY_UI_TEST_DIR)/http_server.o $(CLI_ONLY_UI_TEST_DIR)/test_httpd.o

.PHONY: test-cli-only-ui

$(CLI_ONLY_UI_TEST_DIR):
	mkdir -p $@

$(CLI_ONLY_UI_TEST_DIR)/http_server.o: src/ui/http_server.c $(PROJECT_HDRS) | $(CLI_ONLY_UI_TEST_DIR)
	$(CC) $(CFLAGS_TEST) -Itests -Itests/repro -DCBM_FORK_CLI_ONLY=1 -c -o $@ $<

$(CLI_ONLY_UI_TEST_DIR)/test_httpd.o: tests/test_httpd.c $(PROJECT_HDRS) | $(CLI_ONLY_UI_TEST_DIR)
	$(CC) $(CFLAGS_TEST) -Itests -Itests/repro -DCBM_FORK_CLI_ONLY=1 -c -o $@ $<

$(CLI_ONLY_UI_TEST_RUNNER): $(CLI_ONLY_UI_GUARDED_OBJS) $(ALL_TEST_SRCS) $(PROD_SRCS) $(EXTRACTION_SRCS) $(AC_LZ4_SRCS) $(ZSTD_SRCS) $(SQLITE_WRITER_SRC) $(OBJS_VENDORED_TEST) $(PROJECT_HDRS) | $(CLI_ONLY_UI_TEST_DIR)
	$(CC) $(CFLAGS_TEST) -Itests -Itests/repro -o $@ \
		$(CLI_ONLY_UI_GUARDED_OBJS) \
		$(filter-out $(CLI_ONLY_UI_GUARDED_SRCS),$(ALL_TEST_SRCS) $(PROD_SRCS)) \
		$(EXTRACTION_SRCS) $(AC_LZ4_SRCS) $(ZSTD_SRCS) $(SQLITE_WRITER_SRC) \
		$(OBJS_VENDORED_TEST) \
		$(LDFLAGS_TEST)

test-cli-only-ui: $(CLI_ONLY_UI_TEST_RUNNER)
	@nm $(CLI_ONLY_UI_TEST_DIR)/http_server.o | grep -q "handle_rpc" && \
		{ echo "FAIL: guarded http_server.o still defines handle_rpc"; exit 1; } || true
	cd "$(CURDIR)" && $(CLI_ONLY_UI_TEST_RUNNER) httpd
