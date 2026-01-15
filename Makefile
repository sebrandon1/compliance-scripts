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
        export-compliance update-dashboard serve-docs install-jekyll

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
	@python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations --header none
	@echo "$(GREEN)✅ Combined MachineConfig YAMLs generated!$(RESET)"
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
	@oc -n openshift-compliance get scansettingbinding periodic-e8 || (echo "$(RED)❌ ScanSettingBinding periodic-e8 not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ Periodic scan resources exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 6/9: Asserting periodic scan Profiles exist...$(RESET)"
	@oc -n openshift-compliance get profile ocp4-e8 || (echo "$(RED)❌ Profile ocp4-e8 not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get profile rhcos4-e8 || (echo "$(RED)❌ Profile rhcos4-e8 not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ Profiles ocp4-e8 and rhcos4-e8 exist!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 7/9: Asserting ComplianceSuite for periodic scan exists...$(RESET)"
	@oc -n openshift-compliance get compliancesuite periodic-e8 || (echo "$(RED)❌ ComplianceSuite periodic-e8 not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ ComplianceSuite periodic-e8 exists!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 8/9: Creating CIS scan...$(RESET)"
	@./core/create-scan.sh
	@echo "$(GREEN)✅ CIS scan created!$(RESET)"
	@echo ""
	@echo "$(BOLD)$(MAGENTA)Step 9/9: Asserting on-demand CIS scan resources exist...$(RESET)"
	@oc -n openshift-compliance get scansetting default || (echo "$(RED)❌ ScanSetting default not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get scansettingbinding cis-scan || (echo "$(RED)❌ ScanSettingBinding cis-scan not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get profile ocp4-cis || (echo "$(RED)❌ Profile ocp4-cis not found!$(RESET)" && exit 1)
	@oc -n openshift-compliance get compliancesuite cis-scan || (echo "$(RED)❌ ComplianceSuite cis-scan not found!$(RESET)" && exit 1)
	@echo "$(GREEN)✅ CIS scan resources exist!$(RESET)"
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
	@echo "$(DIM)  ✓ ComplianceSuite periodic-e8 created$(RESET)"
	@echo "$(DIM)  ✓ CIS scan created$(RESET)"
	@echo "$(DIM)  ✓ CIS scan resources and ComplianceSuite exist$(RESET)"
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
	  flake8 . --ignore=E501,E402,W503 --exclude=venv,.venv || (echo "$(RED)❌ Python linting failed!$(RESET)" && exit 1); \
	else \
	  python3 -m flake8 . --ignore=E501,E402,W503 --exclude=venv,.venv || (echo "$(RED)❌ Python linting failed!$(RESET)" && exit 1); \
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
	@find . -name '*.sh' -type f -not -path './venv/*' -not -path './generated-networkpolicies/*' -not -path './complianceremediations/*' -not -path './test-runs/*' -not -path './testing/*' | xargs shellcheck -e SC2034,SC2086,SC2001,SC2028,SC2129,SC2155 || (echo "$(RED)❌ shellcheck failed!$(RESET)" && exit 1)
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
