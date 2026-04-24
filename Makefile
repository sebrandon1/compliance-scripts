# ────────────────────────────────────────────────────────────────────────────────
# 🎨 Color Definitions
# ────────────────────────────────────────────────────────────────────────────────
RESET := \033[0m
BOLD := \033[1m
DIM := \033[2m

# Text Colors
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
MAGENTA := \033[35m
CYAN := \033[36m
WHITE := \033[37m

# Background Colors
BG_RED := \033[41m
BG_GREEN := \033[42m
BG_YELLOW := \033[43m
BG_BLUE := \033[44m

# ────────────────────────────────────────────────────────────────────────────────
# 📋 Target Definitions
# ────────────────────────────────────────────────────────────────────────────────
.PHONY: all help preflight install-compliance-operator apply-periodic-scan create-scan \
        collect-complianceremediations combine-machineconfigs organize-machine-configs \
        generate-compliance-markdown filter-machineconfigs clean clean-complianceremediations \
        full-workflow banner lint python-lint bash-lint verify-images test-compliance \
        export-compliance update-dashboard serve-docs install-jekyll validate-machineconfigs \
        mirror-images rhcos-static-scan

# Default target
all: help

# ────────────────────────────────────────────────────────────────────────────────
# 🎯 Main Targets
# ────────────────────────────────────────────────────────────────────────────────

banner:
	@echo ""
	@echo "$(CYAN)$(BOLD)"
	@echo "  ╔═══════════════════════════════════════════════════════════════╗"
	@echo "  ║           🛡️  COMPLIANCE OPERATOR TOOLKIT  🛡️            ║"
	@echo "  ║                    OpenShift Automation                       ║"
	@echo "  ╚═══════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"

help: banner ## 📖 Show this help message
	@echo "$(BOLD)$(BLUE)Available Commands:$(RESET)"
	@echo ""
	@echo "$(YELLOW)🚀 Workflow Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(workflow|install|apply|create|test-compliance)"
	@echo ""
	@echo "$(YELLOW)📊 Data Collection Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(collect|organize|generate)"
	@echo ""
	@echo "$(YELLOW)🔍 Code Quality Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(lint)"
	@echo ""
	@echo "$(YELLOW)🌐 Dashboard Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(export-compliance|update-dashboard|serve-docs|install-jekyll)"
	@echo ""
	@echo "$(YELLOW)🧹 Utility Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(clean|help|preflight)"
	@echo ""
	@echo "$(DIM)Usage: make <command>$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🔧 Installation & Setup
# ────────────────────────────────────────────────────────────────────────────────

preflight: ## ✅ Check all dependencies and prerequisites
	@./scripts/preflight-check.sh
	@echo ""

verify-images: ## 🔍 Verify container images are accessible before installation
	@echo "$(BOLD)$(BLUE)🔍 Verifying container images...$(RESET)"
	@./utilities/verify-images.sh
	@echo ""

mirror-images: ## 🪞 Mirror compliance-operator images to quay.io/bapalm (requires CO_REF)
	@if [ -z "$(CO_REF)" ]; then \
	  echo "$(RED)❌ Error: CO_REF is required!$(RESET)"; \
	  echo "$(YELLOW)Usage: make mirror-images CO_REF=v1.7.0$(RESET)"; \
	  exit 1; \
	fi
	@if ! command -v skopeo >/dev/null 2>&1; then \
	  echo "$(RED)❌ Error: skopeo is required for mirroring$(RESET)"; \
	  echo "$(DIM)  macOS: brew install skopeo$(RESET)"; \
	  echo "$(DIM)  Linux: dnf install skopeo$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(BLUE)🪞 Mirroring compliance-operator images ($(CO_REF)) to quay.io/bapalm...$(RESET)"
	@DATE=$$(date +%Y-%m-%d); \
	IMAGES="compliance-operator k8scontent compliance-operator-catalog"; \
	for img in $$IMAGES; do \
	  SRC="docker://ghcr.io/complianceascode/$$img:$(CO_REF)"; \
	  DST="docker://quay.io/bapalm/$$img"; \
	  echo "$(DIM)  • $$img:$(CO_REF)$(RESET)"; \
	  skopeo copy --all $$SRC $$DST:$(CO_REF) 2>/dev/null || \
	    (echo "$(YELLOW)  ⚠️  Tag $(CO_REF) not found, trying :latest$(RESET)" && \
	     SRC="docker://ghcr.io/complianceascode/$$img:latest" && \
	     skopeo copy --all $$SRC $$DST:$(CO_REF)); \
	  echo "$(DIM)  • $$img:mirrored-$$DATE$(RESET)"; \
	  skopeo copy --all $$DST:$(CO_REF) $$DST:mirrored-$$DATE; \
	done
	@echo "$(GREEN)✅ Images mirrored to quay.io/bapalm!$(RESET)"
	@echo ""

install-compliance-operator: ## 🔧 Install the OpenShift Compliance Operator
	@echo "$(BOLD)$(BLUE)🔧 Installing Compliance Operator...$(RESET)"
	@./core/install-compliance-operator.sh
	@echo "$(GREEN)✅ Compliance Operator installation completed!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 📋 Scan Management
# ────────────────────────────────────────────────────────────────────────────────

apply-periodic-scan: ## ⏰ Apply periodic compliance scan configuration
	@echo "$(BOLD)$(BLUE)⏰ Applying periodic scan configuration...$(RESET)"
	@./core/apply-periodic-scan.sh
	@echo "$(GREEN)✅ Periodic scan configuration applied!$(RESET)"
	@echo ""

create-scan: ## 🔍 Create a new compliance scan
	@echo "$(BOLD)$(BLUE)🔍 Creating compliance scan...$(RESET)"
	@./core/create-scan.sh
	@echo "$(GREEN)✅ Compliance scan created successfully!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 📊 Data Collection & Processing
# ────────────────────────────────────────────────────────────────────────────────

collect-complianceremediations: ## 📥 Collect compliance remediation data
	@echo "$(BOLD)$(BLUE)📥 Collecting compliance remediations...$(RESET)"
	@./core/collect-complianceremediations.sh
	@echo "$(GREEN)✅ Compliance remediations collected!$(RESET)"
	@echo ""

combine-machineconfigs: ## 🧩 Combine overlapping MachineConfig remediations by file path
	@echo "$(BOLD)$(BLUE)🧩 Combining MachineConfigs by file path...$(RESET)"
	@python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations --header none --no-move
	@echo "$(GREEN)✅ Combined MachineConfig YAMLs generated!$(RESET)"
	@echo ""

validate-machineconfigs: ## ✅ Validate MachineConfig YAML files before applying
	@echo "$(BOLD)$(BLUE)✅ Validating MachineConfig files...$(RESET)"
	@./scripts/validate-machineconfig.sh -d output/machineconfigs 2>/dev/null || ./scripts/validate-machineconfig.sh -d complianceremediations
	@echo ""

detect-conflicts: ## 🔍 Detect file path conflicts between MachineConfig YAMLs
	@echo "$(BOLD)$(BLUE)🔍 Detecting MachineConfig file path conflicts...$(RESET)"
	@./scripts/detect-mc-conflicts.sh -t docs/_data/tracking.json
	@echo ""

filter-machineconfigs: ## 🎯 Filter specific flags from combined MachineConfig (requires INPUT, OUTPUT, and FLAGS or FLAGS_FILE)
	@echo "$(BOLD)$(BLUE)🎯 Filtering MachineConfig flags...$(RESET)"
	@if [ -z "$(INPUT)" ] || [ -z "$(OUTPUT)" ]; then \
	  echo "$(RED)❌ Error: INPUT and OUTPUT are required!$(RESET)"; \
	  echo "$(YELLOW)Usage:$(RESET)"; \
	  echo "  $(CYAN)make filter-machineconfigs INPUT=input.yaml OUTPUT=output.yaml FLAGS=\"flag1 flag2\"$(RESET)"; \
	  echo "  $(CYAN)make filter-machineconfigs INPUT=input.yaml OUTPUT=output.yaml FLAGS_FILE=flags.txt$(RESET)"; \
	  exit 1; \
	fi
	@ARGS=""; \
	if [ -n "$(FLAGS)" ]; then \
	  ARGS="$$ARGS -f $(FLAGS)"; \
	fi; \
	if [ -n "$(FLAGS_FILE)" ]; then \
	  ARGS="$$ARGS --flags-file $(FLAGS_FILE)"; \
	fi; \
	if [ -n "$(DESC)" ]; then \
	  ARGS="$$ARGS -d \"$(DESC)\""; \
	fi; \
	if [ -z "$(FLAGS)" ] && [ -z "$(FLAGS_FILE)" ]; then \
	  echo "$(RED)❌ Error: Either FLAGS or FLAGS_FILE must be specified!$(RESET)"; \
	  exit 1; \
	fi; \
	python3 core/filter-machineconfig-flags.py -i "$(INPUT)" -o "$(OUTPUT)" $$ARGS
	@echo "$(GREEN)✅ Filtered MachineConfig created: $(OUTPUT)$(RESET)"
	@echo ""

organize-machine-configs: ## 📋 Organize machine configuration files
	@echo "$(BOLD)$(BLUE)📋 Organizing machine configurations...$(RESET)"
	@./core/organize-machine-configs.sh
	@echo "$(GREEN)✅ Machine configurations organized!$(RESET)"
	@echo ""

generate-compliance-markdown: ## 📄 Generate compliance report in Markdown format
	@echo "$(BOLD)$(BLUE)📄 Generating compliance markdown report...$(RESET)"
	@./core/generate-compliance-markdown.sh
	@echo "$(GREEN)✅ Compliance markdown report generated!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🧹 Cleanup Operations
# ────────────────────────────────────────────────────────────────────────────────

clean: ## 🧹 Clean up generated files and directories
	@echo "$(BOLD)$(YELLOW)🧹 Cleaning up generated files...$(RESET)"
	@echo "$(DIM)  • Removing complianceremediations directory...$(RESET)"
	@rm -rf complianceremediations/*
	@echo "$(DIM)  • Removing created_file_paths.txt...$(RESET)"
	@rm -f created_file_paths.txt
	@echo "$(DIM)  • Removing ComplianceCheckResults.md...$(RESET)"
	@rm -f ComplianceCheckResults.md
	@echo "$(GREEN)✅ Cleanup completed!$(RESET)"
	@echo ""

clean-complianceremediations: ## 🧹 Remove and recreate the complianceremediations directory only
	@echo "$(BOLD)$(YELLOW)🧹 Resetting complianceremediations directory...$(RESET)"
	@rm -rf complianceremediations
	@mkdir -p complianceremediations
	@echo "$(GREEN)✅ complianceremediations directory reset!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🚀 Workflow Orchestration
# ────────────────────────────────────────────────────────────────────────────────

full-workflow: banner install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations combine-machineconfigs organize-machine-configs generate-compliance-markdown ## 🚀 Execute complete compliance workflow
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║         🎉 FULL COMPLIANCE WORKFLOW COMPLETED! 🎉         ║"
	@echo "  ║              All operations finished successfully            ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo "$(GREEN)📋 Summary of completed operations:$(RESET)"
	@echo "$(DIM)  ✓ Compliance Operator installed$(RESET)"
	@echo "$(DIM)  ✓ Periodic scan configuration applied$(RESET)"
	@echo "$(DIM)  ✓ Compliance scan created$(RESET)"
	@echo "$(DIM)  ✓ Compliance remediations collected$(RESET)"
	@echo "$(DIM)  ✓ Machine configurations organized$(RESET)"
	@echo "$(DIM)  ✓ Compliance markdown report generated$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🧪 Testing & Validation
# ────────────────────────────────────────────────────────────────────────────────

validate-compliance: ## ✅ Validate compliance results against expected baseline
	@echo "$(BOLD)$(BLUE)✅ Validating compliance results...$(RESET)"
	@if [ -z "$(EXPECTED)" ]; then echo "Usage: make validate-compliance EXPECTED=tests/expected-results-4.21.json"; exit 1; fi
	@./tests/validate-results.sh $(EXPECTED)

generate-expected: ## 📋 Generate expected results from live cluster scan data
	@echo "$(BOLD)$(BLUE)📋 Generating expected results...$(RESET)"
	@if [ -z "$(OCP_VERSION)" ]; then echo "Usage: make generate-expected OCP_VERSION=4.22"; exit 1; fi
	@./tests/generate-expected.sh $(OCP_VERSION)

test-compliance: banner ## 🧪 Run compliance validation (same as CI workflow) on local cluster
	@echo "$(BOLD)$(BLUE)🧪 Running compliance validation on local cluster...$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 1/9: Installing Compliance Operator...$(RESET)"
	@./core/install-compliance-operator.sh
	@echo "$(GREEN)✅ Compliance Operator installation completed!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 2/9: Waiting for Compliance Operator pods to be Ready...$(RESET)"
	@oc -n openshift-compliance get pods
	@pods=$$(oc -n openshift-compliance get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); \
	if [ -z "$$pods" ]; then \
		echo "$(RED)❌ No pods found in openshift-compliance namespace!$(RESET)"; \
		exit 1; \
	fi; \
	NSPODS=$$(oc -n openshift-compliance get pods -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' | tr '\n' ' ' | xargs || true); \
	if [ -n "$$NSPODS" ]; then \
		oc -n openshift-compliance wait --for=condition=Ready pod $$NSPODS --timeout=300s; \
	fi
	@echo "$(GREEN)✅ All Compliance Operator pods are Ready!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 3/9: Asserting ProfileBundles exist...$(RESET)"
	@oc -n openshift-compliance get profilebundle ocp4 || (echo "$(RED)❌ ProfileBundle ocp4 not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get profilebundle rhcos4 || (echo "$(RED)❌ ProfileBundle rhcos4 not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ ProfileBundles ocp4 and rhcos4 exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 4/9: Applying periodic scan configuration...$(RESET)"
	@./core/apply-periodic-scan.sh
	@echo "$(GREEN)✅ Periodic scan configuration applied!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 5/9: Asserting periodic scan resources exist...$(RESET)"
	@oc -n openshift-compliance get scansetting periodic-setting || (echo "$(RED)❌ ScanSetting periodic-setting not found!$(RESET)" && exit 1)
	@if oc -n openshift-compliance get profile ocp4-e8 &>/dev/null; then \
		oc -n openshift-compliance get scansettingbinding periodic-e8 || (echo "$(RED)❌ ScanSettingBinding periodic-e8 not found!$(RESET)" && exit 1); \
		echo "$(GREEN)  ✓ periodic-e8 binding exists$(RESET)"; \
	else \
		echo "$(YELLOW)  ⚠ E8 profiles not available, periodic-e8 binding skipped$(RESET)"; \
	fi
	@echo "$(GREEN)✅ Periodic scan resources exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 6/9: Asserting scan Profiles exist...$(RESET)"
	@if oc -n openshift-compliance get profile ocp4-e8 &>/dev/null; then \
		echo "$(GREEN)  ✓ ocp4-e8$(RESET)"; \
	else \
		echo "$(YELLOW)  ⚠ ocp4-e8 not available (may be removed in this operator version)$(RESET)"; \
	fi
	@if oc -n openshift-compliance get profile rhcos4-e8 &>/dev/null; then \
		echo "$(GREEN)  ✓ rhcos4-e8$(RESET)"; \
	else \
		echo "$(YELLOW)  ⚠ rhcos4-e8 not available (may be removed in this operator version)$(RESET)"; \
	fi
	@oc -n openshift-compliance get profile ocp4-cis || (echo "$(RED)❌ Profile ocp4-cis not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get profile ocp4-moderate || (echo "$(RED)❌ Profile ocp4-moderate not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ Required profiles exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 7/9: Asserting ComplianceSuites for periodic scans exist...$(RESET)"
	@if oc -n openshift-compliance get profile ocp4-e8 &>/dev/null; then \
		oc -n openshift-compliance get compliancesuite periodic-e8 || (echo "$(RED)❌ ComplianceSuite periodic-e8 not found!$(RESET)" && exit 1); \
		echo "$(GREEN)  ✓ ComplianceSuite periodic-e8 exists$(RESET)"; \
	else \
		echo "$(YELLOW)  ⚠ ComplianceSuite periodic-e8 skipped (E8 profiles not available)$(RESET)"; \
	fi
	@oc -n openshift-compliance get compliancesuite cis-scan || (echo "$(RED)❌ ComplianceSuite cis-scan not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ ComplianceSuites exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 8/9: Creating compliance scans (all profiles)...$(RESET)"
	@./core/create-scan.sh
	@echo "$(GREEN)✅ Compliance scans created!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 9/9: Asserting on-demand scan resources exist...$(RESET)"
	@oc -n openshift-compliance get scansetting default || (echo "$(RED)❌ ScanSetting default not found!$(RESET)" && exit 1)
	@for profile in ocp4-cis ocp4-moderate ocp4-pci-dss rhcos4-moderate; do \
		oc -n openshift-compliance get scansettingbinding $${profile}-scan || (echo "$(RED)❌ ScanSettingBinding $${profile}-scan not found!$(RESET)" && exit 1); \
	done
	@for profile in ocp4-e8 rhcos4-e8; do \
		if oc -n openshift-compliance get profile $${profile} &>/dev/null; then \
			oc -n openshift-compliance get scansettingbinding $${profile}-scan || (echo "$(RED)❌ ScanSettingBinding $${profile}-scan not found!$(RESET)" && exit 1); \
		else \
			echo "$(YELLOW)  ⚠ $${profile}-scan skipped (profile not available)$(RESET)"; \
		fi; \
	done
	@echo "$(GREEN)✅ All scan resources exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(BG_GREEN)$(WHITE)"
	@echo "  ╔═════════════════════════════════════════════════════════════╗"
	@echo "  ║       🎉 COMPLIANCE VALIDATION COMPLETED SUCCESSFULLY! 🎉   ║"
	@echo "  ║              All assertions passed!                         ║"
	@echo "  ╚═════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo "$(GREEN)📋 Validation Summary:$(RESET)"
	@echo "$(DIM)  ✓ Compliance Operator installed and pods Ready$(RESET)"
	@echo "$(DIM)  ✓ ProfileBundles ocp4 and rhcos4 exist$(RESET)"
	@echo "$(DIM)  ✓ Periodic scan configuration applied$(RESET)"
	@echo "$(DIM)  ✓ Periodic scan resources and profiles exist$(RESET)"
	@echo "$(DIM)  ✓ ComplianceSuites created for available profiles$(RESET)"
	@echo "$(DIM)  ✓ All compliance scans created for available profiles$(RESET)"
	@echo "$(DIM)  ✓ All scan resources and ComplianceSuites exist$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🔍 Code Quality & Linting
# ────────────────────────────────────────────────────────────────────────────────

lint: python-lint bash-lint ## 🔍 Run all linters (Python + Bash)
	@echo ""
	@echo "$(BOLD)$(GREEN)✅ All linting checks passed!$(RESET)"
	@echo ""

python-lint: ## 🐍 Lint Python files with flake8
	@echo "$(BOLD)$(BLUE)🐍 Linting Python files...$(RESET)"
	@if ! command -v flake8 >/dev/null 2>&1 && ! python3 -m flake8 --version >/dev/null 2>&1; then \
	  echo "$(YELLOW)⚙️  flake8 not found, installing...$(RESET)"; \
	  pip3 install --user --break-system-packages flake8 2>/dev/null || pip3 install --user flake8; \
	fi
	@if command -v flake8 >/dev/null 2>&1; then \
	  flake8 . --ignore=E501,E402,W503 --exclude=venv,.venv,docs/vendor || (echo "$(RED)❌ Python linting failed!$(RESET)" && exit 1); \
	else \
	  python3 -m flake8 . --ignore=E501,E402,W503 --exclude=venv,.venv,docs/vendor || (echo "$(RED)❌ Python linting failed!$(RESET)" && exit 1); \
	fi
	@echo "$(GREEN)✅ Python linting passed!$(RESET)"

bash-lint: ## 📜 Lint Bash scripts with shellcheck and shfmt
	@echo "$(BOLD)$(BLUE)📜 Linting Bash scripts...$(RESET)"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "$(RED)❌ shellcheck not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shellcheck$(RESET)"; \
	  echo "$(DIM)  Linux: apt-get install shellcheck or dnf install ShellCheck$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(DIM)  • Running shellcheck...$(RESET)"
	@find . -name '*.sh' -type f -not -path './venv/*' -not -path './generated-networkpolicies/*' -not -path './complianceremediations/*' -not -path './test-runs/*' -not -path './testing/*' -not -path './docs/vendor/*' | xargs shellcheck -e SC1091,SC2034,SC2086,SC2001,SC2028,SC2129,SC2155 || (echo "$(RED)❌ shellcheck failed!$(RESET)" && exit 1)
	@if ! command -v shfmt >/dev/null 2>&1; then \
	  echo "$(RED)❌ shfmt not found. Please install it:$(RESET)"; \
	  echo "$(DIM)  macOS: brew install shfmt$(RESET)"; \
	  echo "$(DIM)  Linux: go install mvdan.cc/sh/v3/cmd/shfmt@latest$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(DIM)  • Running shfmt...$(RESET)"
	@shfmt -d core utilities modular lab-tools misc || (echo "$(RED)❌ shfmt formatting check failed!$(RESET)" && echo "$(YELLOW)💡 To automatically fix formatting issues, run:$(RESET)" && echo "$(CYAN)   shfmt -w core utilities modular lab-tools misc$(RESET)" && exit 1)
	@echo "$(GREEN)✅ Bash linting passed!$(RESET)"

# ────────────────────────────────────────────────────────────────────────────────
# 🌐 Compliance Dashboard (GitHub Pages)
# ────────────────────────────────────────────────────────────────────────────────

export-compliance: ## 📊 Export compliance data to JSON for dashboard (requires OCP_VERSION)
	@if [ -z "$(OCP_VERSION)" ]; then \
	  echo "$(RED)❌ Error: OCP_VERSION is required!$(RESET)"; \
	  echo "$(YELLOW)Usage: make export-compliance OCP_VERSION=4.17$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(BLUE)📊 Exporting compliance data for OCP $(OCP_VERSION)...$(RESET)"
	@./core/export-compliance-data.sh $(OCP_VERSION)
	@echo "$(GREEN)✅ Compliance data exported to docs/_data/ocp-$(OCP_VERSION).json$(RESET)"
	@echo ""

update-dashboard: ## 🔄 Export compliance data and push to trigger dashboard rebuild
	@if [ -z "$(OCP_VERSION)" ]; then \
	  echo "$(RED)❌ Error: OCP_VERSION is required!$(RESET)"; \
	  echo "$(YELLOW)Usage: make update-dashboard OCP_VERSION=4.17$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(BLUE)🔄 Updating compliance dashboard for OCP $(OCP_VERSION)...$(RESET)"
	@./core/export-compliance-data.sh $(OCP_VERSION)
	@git add docs/_data/
	@git commit -m "Update compliance data for OCP $(OCP_VERSION)"
	@git push
	@echo "$(GREEN)✅ Dashboard update pushed! GitHub Actions will rebuild the site.$(RESET)"
	@echo ""

serve-docs: ## 🖥️  Serve the compliance dashboard locally (requires Jekyll)
	@echo "$(BOLD)$(BLUE)🖥️  Starting local Jekyll server...$(RESET)"
	@echo "$(DIM)  Visit http://localhost:4000 to view the dashboard$(RESET)"
	@cd docs && bundle exec jekyll serve

install-jekyll: ## 💎 Install Jekyll dependencies for local dashboard development
	@echo "$(BOLD)$(BLUE)💎 Installing Jekyll dependencies...$(RESET)"
	@cd docs && bundle install --path vendor/bundle
	@echo "$(GREEN)✅ Jekyll dependencies installed!$(RESET)"
	@echo ""

rhcos-static-scan: ## 🔬 Run offline OSCAP scan against RHCOS rootfs (requires OCP_VERSION)
	@if [ -z "$(OCP_VERSION)" ]; then \
	  echo "$(RED)❌ Error: OCP_VERSION is required!$(RESET)"; \
	  echo "$(YELLOW)Usage: make rhcos-static-scan OCP_VERSION=4.21$(RESET)"; \
	  exit 1; \
	fi
	@echo "$(BOLD)$(BLUE)🔬 Running offline RHCOS compliance scan for OCP $(OCP_VERSION)...$(RESET)"
	@./scripts/rhcos-static-scan.sh $(OCP_VERSION)
	@echo ""
