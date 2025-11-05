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
BG_GREEN := \033[42m
BG_YELLOW := \033[43m

# ────────────────────────────────────────────────────────────────────────────────
# 📋 Target Definitions
# ────────────────────────────────────────────────────────────────────────────────
.PHONY: all help baseline validate functional test-high test-medium test-low clean

# Default target
all: help

# ────────────────────────────────────────────────────────────────────────────────
# 🎯 Help Target
# ────────────────────────────────────────────────────────────────────────────────

help: ## 📖 Show this help message
	@echo ""
	@echo "$(CYAN)$(BOLD)"
	@echo "  ╔═══════════════════════════════════════════════════════════════╗"
	@echo "  ║       🧪 COMPLIANCE REMEDIATION TESTING FRAMEWORK 🧪      ║"
	@echo "  ║              Validate Remediations Safely                     ║"
	@echo "  ╚═══════════════════════════════════════════════════════════════╝"
	@echo "$(RESET)"
	@echo "$(BOLD)$(BLUE)Available Commands:$(RESET)"
	@echo ""
	@echo "$(YELLOW)🧪 Individual Test Components:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(baseline|validate|functional)"
	@echo ""
	@echo "$(YELLOW)🚀 End-to-End Testing:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(test-)"
	@echo ""
	@echo "$(YELLOW)🧹 Cleanup:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | grep -E "(clean)"
	@echo ""
	@echo "$(DIM)Usage: make <command>$(RESET)"
	@echo "$(DIM)See README.md for detailed documentation$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🧪 Individual Test Components
# ────────────────────────────────────────────────────────────────────────────────

baseline: ## 🧪 Capture cluster baseline before applying remediations
	@echo "$(BOLD)$(BLUE)🧪 Capturing cluster baseline...$(RESET)"
	@python3 capture-baseline.py
	@echo "$(GREEN)✅ Baseline captured successfully!$(RESET)"
	@echo ""

validate: ## 🧪 Validate cluster health against baseline
	@echo "$(BOLD)$(BLUE)🧪 Validating cluster health...$(RESET)"
	@python3 validate-cluster-health.py
	@echo "$(GREEN)✅ Validation completed!$(RESET)"
	@echo ""

functional: ## 🧪 Run functional tests on OCP capabilities
	@echo "$(BOLD)$(BLUE)🧪 Running functional tests...$(RESET)"
	@python3 test-ocp-functionality.py
	@echo "$(GREEN)✅ Functional tests completed!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🚀 End-to-End Testing
# ────────────────────────────────────────────────────────────────────────────────

test-high: baseline ## 🚀 Test HIGH severity remediations end-to-end
	@echo "$(BOLD)$(MAGENTA)🚀 Testing HIGH severity remediations...$(RESET)"
	@./run-compliance-tests.sh high
	@echo "$(GREEN)✅ HIGH severity remediation testing completed!$(RESET)"
	@echo ""

test-medium: baseline ## 🚀 Test MEDIUM severity remediations end-to-end
	@echo "$(BOLD)$(MAGENTA)🚀 Testing MEDIUM severity remediations...$(RESET)"
	@./run-compliance-tests.sh medium
	@echo "$(GREEN)✅ MEDIUM severity remediation testing completed!$(RESET)"
	@echo ""

test-low: baseline ## 🚀 Test LOW severity remediations end-to-end
	@echo "$(BOLD)$(MAGENTA)🚀 Testing LOW severity remediations...$(RESET)"
	@./run-compliance-tests.sh low
	@echo "$(GREEN)✅ LOW severity remediation testing completed!$(RESET)"
	@echo ""

# ────────────────────────────────────────────────────────────────────────────────
# 🧹 Cleanup Operations
# ────────────────────────────────────────────────────────────────────────────────

clean: ## 🧹 Clean up test run results and baselines
	@echo "$(BOLD)$(YELLOW)🧹 Cleaning test results...$(RESET)"
	@rm -rf ../test-runs/
	@rm -f ../cluster-baseline-*.json ../cluster-validation-*.json ../functional-test-results-*.json
	@rm -f ../applied-yamls-*.txt
	@echo "$(GREEN)✅ Test results cleaned!$(RESET)"
	@echo ""

