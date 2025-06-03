# Makefile for OpenShift Compliance Operator automation

.PHONY: all install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations create-source-comments combine-machineconfigs-by-path organize-machine-configs generate-compliance-markdown clean full-workflow python-lint

all: full-workflow

install-compliance-operator:
	./install-compliance-operator.sh

apply-periodic-scan:
	./apply-periodic-scan.sh

create-scan:
	./create-scan.sh

collect-complianceremediations:
	./collect-complianceremediations.sh

create-source-comments:
	python3 create-source-comments.py --src-dir complianceremediations

combine-machineconfigs-by-path:
	python3 combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations

organize-machine-configs:
	./organize-machine-configs.sh

generate-compliance-markdown:
	./generate-compliance-markdown.sh

clean:
	rm -rf complianceremediations/* created_file_paths.txt ComplianceCheckResults.md

full-workflow: install-compliance-operator apply-periodic-scan create-scan collect-complianceremediations create-source-comments combine-machineconfigs-by-path organize-machine-configs generate-compliance-markdown
	@echo "[INFO] Full compliance workflow completed."

python-lint:
	@if ! command -v flake8 >/dev/null 2>&1; then \
	  echo 'flake8 not found, installing...'; \
	  pip3 install --user flake8; \
	fi
	flake8 . --ignore=E501 --exclude=venv,.venv
