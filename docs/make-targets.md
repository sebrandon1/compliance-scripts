# Make Targets

```bash
# Workflow
make full-workflow                    # Run the entire compliance pipeline
make preflight                        # Check all dependencies
make wait-for-scans                   # Wait until all ComplianceSuites are DONE

# Installation and scanning
make install-compliance-operator      # Install the operator
make apply-periodic-scan              # Set up daily scans
make create-scan                      # Run an on-demand scan (all profiles)

# Collection and processing
make collect-complianceremediations   # Extract remediations from cluster
make combine-machineconfigs           # Merge overlapping MachineConfigs
make organize-machine-configs         # Categorize by topic
make generate-compliance-markdown     # Generate report

# Validation
make validate-machineconfigs          # Validate MachineConfig YAML files
make filter-machineconfigs            # Filter specific flags (requires INPUT, OUTPUT, FLAGS)
make detect-conflicts                 # Detect file path conflicts between MachineConfigs
make verify-images                    # Verify container images are accessible
make test-compliance                  # Run full CI validation on local cluster
make python-test                      # Run Python unit tests (pytest)
make shell-smoke-test                 # bash -n syntax checks
make validate-compliance EXPECTED=tests/expected-results-5.0.json
make generate-expected OCP_VERSION=5.0
make suggest-groups SCAN=docs/_data/ocp-5_0.json
make diff-scans OLD=old.json NEW=new.json
make validate-dashboard-data          # Validate docs/_data JSON
make dashboard-validate               # Alias for validate-dashboard-data

# Dashboard
make export-compliance OCP_VERSION=5.0    # Export scan data to JSON
make generate-group-matrix                # Rebuild Hardened page group-matrix.json
make backfill-scan-profiles               # Fill missing per-profile counts in scan-history.json
make update-dashboard OCP_VERSION=5.0     # Export, validate, and open a PR
make add-version OCP_VERSION=5.1 SOURCE_VERSION=5.0
make serve-docs                           # Serve dashboard locally
make install-jekyll                       # Install Jekyll dependencies

# Images
make mirror-images CO_REF=v1.9.0          # Mirror operator images
make rhcos-static-scan OCP_VERSION=4.21   # Offline OSCAP scan of RHCOS rootfs

# Linting
make lint                             # Run all linters (Python + Bash)
make python-lint                      # flake8 + mypy
make bash-lint                        # shellcheck + shfmt

# Cleanup
make clean                            # Remove generated files
make clean-complianceremediations     # Reset complianceremediations directory
```
