# Make Targets

```bash
# Workflow
make full-workflow                    # Run the entire compliance pipeline
make preflight                        # Check all dependencies

# Installation and scanning
make install-compliance-operator      # Install the operator
make apply-periodic-scan              # Set up daily scans
make create-scan                      # Run an on-demand scan

# Collection and processing
make collect-complianceremediations   # Extract remediations from cluster
make combine-machineconfigs           # Merge overlapping MachineConfigs
make organize-machine-configs         # Categorize by topic
make generate-compliance-markdown     # Generate report

# Validation
make validate-machineconfigs          # Validate MachineConfig YAML files
make filter-machineconfigs            # Filter specific flags (requires INPUT, OUTPUT, FLAGS)
make verify-images                    # Verify container images are accessible
make test-compliance                  # Run full CI validation on local cluster

# Dashboard
make export-compliance OCP_VERSION=4.22   # Export scan data to JSON
make update-dashboard OCP_VERSION=4.22    # Export and push to trigger rebuild
make serve-docs                           # Serve dashboard locally
make install-jekyll                       # Install Jekyll dependencies

# Linting
make lint                             # Run all linters (Python + Bash)
make python-lint                      # Python only (flake8)
make bash-lint                        # Bash only (shellcheck + shfmt)

# Cleanup
make clean                            # Remove generated files
make clean-complianceremediations     # Reset complianceremediations directory
```
