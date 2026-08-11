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

---

## Customer-Facing Guides

### `guides/okta-scim-saml-setup-guide.html`

**Okta SCIM + SAML Setup Guide for Iru Endpoint**

An interactive HTML worksheet for configuring a single Okta custom SAML 2.0 app to handle both SCIM provisioning and SAML enrollment authentication for Iru Endpoint. The customer pastes six tenant values into the ledger at the top and all steps fill in live — no copy-paste errors, no placeholder URLs.

**Audience:** Customers and prospects. The file contains no Iru- or customer-specific data; it is safe to share with anyone evaluating the integration.

**Self-contained and offline.** Zero external dependencies. A Content Security Policy (`default-src 'none'`) enforced by the browser blocks all network activity — nothing entered can be transmitted. Values are held in JavaScript memory only; closing the tab clears everything. No storage (no localStorage, sessionStorage, or cookies).

Steps confirmed against docs.iru.com (SCIM Directory Integration with Okta; Single Sign-On with Okta SAML) and field-validated end to end in a test tenant, July 2026.

**Delivery:** Share as a file download or walk through it live. **Do not send as an email attachment** — HTML attachments are quarantined by most mail security gateways before they reach the recipient.

**File integrity (SHA-256):**

```
ccdc7f854b3e251c40c357b94e2e6b42ac7ccc68704dad3fd770ad966cc6ebcc
```

This hash is shared with customers so they can confirm the copy they received is unmodified (`shasum -a 256 okta-scim-saml-setup-guide.html` on macOS/Linux; `Get-FileHash` on Windows). Recompute and update this entry after any future edit to the file.
