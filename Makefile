# Makefile for OpenShift Compliance Operator automation

.PHONY: all install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations organize-machine-configs generate-compliance-markdown clean full-workflow

all: full-workflow

install-compliance-operator:
	./install-compliance-operator.sh

apply-periodic-scan:
	./apply-periodic-scan.sh

create-scan:
	./create-scan.sh

collect-complianceremediations:
	./collect-complianceremediations.sh

organize-machine-configs:
	./organize-machine-configs.sh

generate-compliance-markdown:
	./generate-compliance-markdown.sh

clean:
	rm -rf complianceremediations/* created_file_paths.txt ComplianceCheckResults.md

full-workflow: install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations organize-machine-configs generate-compliance-markdown
	@echo "[INFO] Full compliance workflow completed."
