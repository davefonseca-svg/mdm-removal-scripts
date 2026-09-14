# Contributing

This is a private, single-maintainer staging repository. Full contributor workflow (CODEOWNERS, required reviews, branch protection, CI enforcement) belongs in the org repo. The rules here are the ones that apply regardless of repository scale.

## Before writing any script

Read, in order:

1. [`MDM_Removal_Script_Standard.md`](MDM_Removal_Script_Standard.md) — the operator contract (C1–C12); non-negotiable
2. [`SECURITY_PHILOSOPHY.md`](SECURITY_PHILOSOPHY.md) — threat model and per-script security reviews
3. [`CLAUDE.md`](CLAUDE.md) — everyday engineering requirements

## Starting a new script

Start from the template for the target platform. Never copy-paste from an existing vendor script — that is how the Chef-block bug family happens.

Complete every item in the template AUTHOR CHECKLIST before any customer use.

## Non-negotiable rules

- No customer data anywhere — no tenant IDs, GUIDs, enrollment codes, hostnames, usernames, or email addresses in code, comments, changelogs, or docs. Changelogs cite dates and generic findings only.
- No hardcoded secrets.
- Scripts ship with `DRY_RUN="true"` / `$DryRun = $true`. No exceptions.
- No unconditional success logging. Every removal verifies its own result.
- Follow the execution lifecycle: **Detect → Validate → Execute → Verify**.
- Wildcard sweeps stay broad (rule 8). Do not narrow to a single tenant's artifact list.
- Flag-gate irreversible or shared-dependency items (accounts, shared tooling). Default: off.

## Static analysis and syntax validation

**macOS:** `zsh -n <script.sh>` for syntax; then the logic smoke tests from the contract verification workflow.

**Windows:** `Invoke-ScriptAnalyzer -Path windows\ -Recurse`. Use `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` for intentional deviations — narrow and documented.

## Before every commit

Review the entire diff:

- [ ] No customer data
- [ ] No secrets or credentials
- [ ] No hardcoded paths to specific customer environments
- [ ] No unsafe deletion (unvalidated variable, no post-action verify)
- [ ] No unconditional success logging
- [ ] Version bumped if behavior changed; README updated; header changelog entry added
- [ ] Syntax validation passed

## Version bumps

Semver per contract C12. Patch = bug fix. Minor = new artifact coverage or flags. Major = contract-visible behavioral change. Version variable, header changelog, runtime banner, README version history, and Overview PDF all move together in the same commit.

## Commit messages

Engineering change, not customer incident. "Fix Phase 1d process check to use PID-snapshot pattern" — good. "Fix bug found on device" — bad.

---

## FOR THE ORG REPO

The following should be added when this repository moves to the org:

- Branch protection on `main`: require PR, at least one reviewer, no direct push
- GitHub secret scanning and push protection enabled
- Required status checks: `zsh -n` for macOS scripts; PSScriptAnalyzer for Windows scripts
- CI job: `zsh -n` on every modified `.sh`; `Invoke-ScriptAnalyzer` on every modified `.ps1`
- CODEOWNERS file
- Custom secret-scanning patterns for enrollment-code and tenant-ID formats
- SECURITY.md reporting contact filled in (currently a placeholder)
