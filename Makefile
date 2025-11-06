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
.PHONY: all help install-compliance-operator apply-periodic-scan create-scan \
        collect-complianceremediations combine-machineconfigs organize-machine-configs \
        generate-compliance-markdown clean clean-complianceremediations full-workflow banner \
        lint python-lint bash-lint

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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(workflow|install|apply|create)"
	@echo ""
	@echo "$(YELLOW)📊 Data Collection Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(collect|organize|generate)"
	@echo ""
	@echo "$(YELLOW)🔍 Code Quality Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(lint)"
	@echo ""
	@echo "$(YELLOW)🧹 Utility Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(clean|help)"
	@echo ""
	@echo "$(DIM)Usage: make <command>$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🔧 Installation & Setup
# ────────────────────────────────────────────────────────────────────────────────

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
