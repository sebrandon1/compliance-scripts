# Compliance Remediation Groupings

This page provides links to remediation groupings organized by OCP version. Each version has its own set of compliance remediations collected from the OpenShift Compliance Operator.

---

## Available Versions

| OCP Version | Groups | Remediations | Status |
|-------------|--------|--------------|--------|
| [**OCP 5.0**](versions/5.0/remediations.html) | 40 groups | 914 total | Active |
| [**OCP 4.22**](versions/4.22/remediations.html) | 40 groups (33 tested) | 910 total | Active |
| [**OCP 4.21**](versions/4.21/remediations.html) | 17 groups | 82 total | Active |

---

## About Remediation Groupings

Remediation groupings consolidate individual compliance check failures into logical groups that can be addressed together. Each group typically results in a single MachineConfig or CRD that remediates multiple related checks.

**Grouping Categories:**
- **SSHD Hardening** - SSH daemon security settings
- **Kernel Sysctl** - Kernel security parameters
- **Audit Rules** - System auditing configuration
- **Crypto Policy** - Cryptographic standards
- **API Server** - OpenShift API server settings
- **PAM Configuration** - Pluggable Authentication Modules

**Status Legend:**
- 🔵 **In Progress** - Active PR open for remediation
- 🟡 **Pending** - Not yet started
- ⚪ **On Hold** - Paused (e.g., focusing on higher severity first)
- 🟢 **Complete** - Merged and verified

---

## Adding a New Version

To add remediation groupings for a new OCP version:

```bash
make add-version OCP_VERSION=5.1 SOURCE_VERSION=5.0
```

That scaffolds version pages, group pages, and `docs/_data/tracking-X_Y.json`. Then:

1. Export scan data: `make export-compliance OCP_VERSION=5.1`
2. Update this index page with a link to the new version
3. Refresh `docs/_data/group-matrix.json` with `make generate-group-matrix`
4. Fill missing scan-history profile counts with `make backfill-scan-profiles`
