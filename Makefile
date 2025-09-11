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
        collect-complianceremediations organize-machine-configs \
        generate-compliance-markdown clean clean-complianceremediations full-workflow banner

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
	@./install-compliance-operator.sh
	@echo "$(GREEN)✅ Compliance Operator installation completed!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 📋 Scan Management
# ────────────────────────────────────────────────────────────────────────────────

apply-periodic-scan: ## ⏰ Apply periodic compliance scan configuration
	@echo "$(BOLD)$(BLUE)⏰ Applying periodic scan configuration...$(RESET)"
	@./apply-periodic-scan.sh
	@echo "$(GREEN)✅ Periodic scan configuration applied!$(RESET)"
	@echo ""

create-scan: ## 🔍 Create a new compliance scan
	@echo "$(BOLD)$(BLUE)🔍 Creating compliance scan...$(RESET)"
	@./create-scan.sh
	@echo "$(GREEN)✅ Compliance scan created successfully!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 📊 Data Collection & Processing
# ────────────────────────────────────────────────────────────────────────────────

collect-complianceremediations: ## 📥 Collect compliance remediation data
	@echo "$(BOLD)$(BLUE)📥 Collecting compliance remediations...$(RESET)"
	@./collect-complianceremediations.sh
	@echo "$(GREEN)✅ Compliance remediations collected!$(RESET)"
	@echo ""

organize-machine-configs: ## 📋 Organize machine configuration files
	@echo "$(BOLD)$(BLUE)📋 Organizing machine configurations...$(RESET)"
	@./organize-machine-configs.sh
	@echo "$(GREEN)✅ Machine configurations organized!$(RESET)"
	@echo ""

generate-compliance-markdown: ## 📄 Generate compliance report in Markdown format
	@echo "$(BOLD)$(BLUE)📄 Generating compliance markdown report...$(RESET)"
	@./generate-compliance-markdown.sh
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

full-workflow: banner install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations organize-machine-configs generate-compliance-markdown ## 🚀 Execute complete compliance workflow
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

python-lint:
	@if ! command -v flake8 >/dev/null 2>&1; then \
	  echo 'flake8 not found, installing...'; \
	  pip3 install --user flake8; \
	fi
	flake8 . --ignore=E501 --exclude=venv,.venv
