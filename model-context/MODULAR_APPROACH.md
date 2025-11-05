# Modular MachineConfig Approach

## Overview

This repository now supports creating **modular** MachineConfig files that use `.d` directory includes instead of monolithic configuration files. This approach makes individual remediations easier to review, manage, and apply incrementally.

## The Problem with Combo Files

Previously, `combine-machineconfigs-by-path.py` would merge all remediations targeting the same file (e.g., `/etc/ssh/sshd_config`) into a single large "combo" file. This had several drawbacks:

- **Hard to review**: Large files with many settings are difficult to review in PRs
- **All-or-nothing**: You had to apply all settings at once, no incremental adoption
- **Difficult to track**: Hard to see which remediation was responsible for which setting

Example of old combo approach:
```yaml
# sshd_config-high-combo.yaml
# Overwrites entire /etc/ssh/sshd_config with all settings combined
```

## The New Modular Approach

The new `split-machineconfigs-modular.py` script creates:

1. **Base files** that enable `.d` include directories
2. **Individual modular files** for each remediation, placed in the `.d` directory

### Example Structure

For SSH configuration:
```
75-sshd_config-base-high.yaml
  ↳ Creates /etc/ssh/sshd_config.d/00-include.conf
    ↳ Contains: Include /etc/ssh/sshd_config.d/*.conf

76-sshd_config-disable-root-login-worker-high.yaml
  ↳ Creates /etc/ssh/sshd_config.d/76-disable-root-login.conf
    ↳ Contains: PermitRootLogin no

77-sshd_config-disable-password-auth-worker-high.yaml
  ↳ Creates /etc/ssh/sshd_config.d/77-disable-password-auth.conf
    ↳ Contains: PasswordAuthentication no, PermitEmptyPasswords no
```

### Benefits

✅ **Easier to review** - Each PR contains only the specific settings being changed  
✅ **Incremental adoption** - Apply remediations one at a time  
✅ **Better traceability** - Clear mapping between remediation and configuration  
✅ **Follows best practices** - Uses standard `.d` directory pattern  
✅ **Compatible with PR #439** - Matches the approach from the telco-reference PR

## Supported Paths

Currently, the modular approach supports:

| Original Path | Include Directory | Base File |
|--------------|-------------------|-----------|
| `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config.d/` | `00-include.conf` |
| `/etc/pam.d/system-auth` | `/etc/pam.d/system-auth.d/` | `00-include` |
| `/etc/pam.d/password-auth` | `/etc/pam.d/password-auth.d/` | `00-include` |

Paths not in this list will fall back to the combo file approach.

## Usage

### Quick Start

```bash
# Create modular files for high-severity remediations
./create-modular-configs.sh -s high

# Review generated files
ls -la complianceremediations/modular/

# Organize into target repository structure
./organize-machine-configs.sh -d complianceremediations/modular -s high
```

### Manual Usage

```bash
# Activate Python virtual environment
source venv/bin/activate

# Create modular files
python3 split-machineconfigs-modular.py \
  --src-dir complianceremediations \
  --out-dir complianceremediations/modular \
  -s high

# Or use the wrapper script
./create-modular-configs.sh -s high,medium
```

### Options

```bash
# Process multiple severity levels
./create-modular-configs.sh -s high,medium,low

# Specify custom directories
./create-modular-configs.sh \
  -i complianceremediations \
  -o output/modular \
  -s high
```

## Integration with Existing Workflow

The modular approach integrates seamlessly with the existing workflow:

```bash
# 1. Install compliance operator and run scans
./install-compliance-operator.sh
./apply-periodic-scan.sh

# 2. Collect remediations
./collect-complianceremediations.sh

# 3. OLD WAY: Combine into monolithic files
# python3 combine-machineconfigs-by-path.py -s high

# 3. NEW WAY: Create modular files
./create-modular-configs.sh -s high

# 4. Organize into target repository
./organize-machine-configs.sh -d complianceremediations/modular -s high
```

## Comparison: Combo vs Modular

### Combo Approach (Old)
```yaml
# One large file with all settings
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 75-sshd_config-high-combo
spec:
  config:
    storage:
      files:
      - path: /etc/ssh/sshd_config
        contents: |
          # 100+ lines of complete sshd_config
          PermitRootLogin no
          PasswordAuthentication no
          ClientAliveInterval 300
          ... many more settings ...
```

### Modular Approach (New)
```yaml
# Base file
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 75-sshd_config-base-high
spec:
  config:
    storage:
      files:
      - path: /etc/ssh/sshd_config.d/00-include.conf
        contents: |
          Include /etc/ssh/sshd_config.d/*.conf

---
# Individual modular file
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 76-sshd_config-disable-root-login-worker-high
spec:
  config:
    storage:
      files:
      - path: /etc/ssh/sshd_config.d/76-disable-root-login.conf
        contents: |
          PermitRootLogin no
```

## Adding New Modular Paths

To add support for additional configuration files:

1. Edit `split-machineconfigs-modular.py`
2. Add entry to the `MODULAR_PATHS` dictionary:

```python
MODULAR_PATHS = {
    '/your/config/file': {
        'include_dir': '/your/config/file.d',
        'base_file': '00-include.conf',
        'base_content': 'Include /your/config/file.d/*.conf',
        'file_extension': '.conf',
    },
    # ... existing entries
}
```

## Troubleshooting

### No files generated
- Check that remediations exist in the source directory
- Verify severity filter matches your files
- Ensure files target modular paths (sshd_config, pam.d)

### Virtual environment issues
```bash
# Recreate virtual environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Validation
```bash
# Validate generated YAML files
for file in complianceremediations/modular/*.yaml; do
  echo "Checking $file..."
  oc apply --dry-run=server -f "$file"
done
```

## References

- [PR #439](https://github.com/openshift-kni/telco-reference/pull/439) - RAN Hardening (High): Top 5 SSHD
- [Compliance Operator](https://github.com/ComplianceAsCode/compliance-operator)
- [OpenShift MachineConfig](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)

