# mdm-removal-scripts

Iru Solutions Engineering tooling: post-migration MDM removal scripts and customer-facing setup guides.

For engineering standards, see [`CLAUDE.md`](CLAUDE.md) and [`SECURITY_PHILOSOPHY.md`](SECURITY_PHILOSOPHY.md).
For the operator contract that every removal script must satisfy, see [`MDM_Removal_Script_Standard.md`](MDM_Removal_Script_Standard.md).

---

## MDM Removal Scripts

Self-contained removal kits for each incumbent MDM platform, organized by OS and vendor. Each kit ships in dry-run mode by default; a live run requires explicitly flipping one variable.

| Script | Platform | Version | Status |
|---|---|---|---|
| `macos/rippling/rippling_removal_macos.sh` | macOS | 2.0.3 | Parser-validated; field-verified 2026-07-14 |
| `windows/rippling/rippling_removal_windows.ps1` | Windows | 1.3.1 | Parser-validated; field-verified 2026-07-13 |

Template for new scripts: `templates/template_removal_macos.sh`

