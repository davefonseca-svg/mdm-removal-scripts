# Security Policy

## Scope

This repository contains privileged endpoint-management scripts that may run as root or Administrator and modify MDM agent state, system services, processes, files, and registry configuration. Security issues in this tooling may affect many managed devices.

## Supported Versions

Security fixes are applied to the current version of each script. Older versions in Git history are not actively maintained.

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Public issue disclosure may expose exploitable details before a fix is available.

To report a vulnerability:

1. Email **[SECURITY-CONTACT-TO-BE-PROVIDED]** with the subject line: `[SECURITY] mdm-removal-scripts — <brief description>`
2. Include:
   - A description of the vulnerability and its potential impact
   - The affected file(s) and version(s)
   - Steps to reproduce or a proof-of-concept (using generic/synthetic data only — no real customer data)
   - Your assessment of severity
   - Any suggested remediation

We will acknowledge receipt within **[SLA-TO-BE-PROVIDED]** and provide an initial assessment within **[SLA-TO-BE-PROVIDED]**.

**Note to repository owner:** Replace the bracketed placeholders above with a real security contact email address and response SLA before this repository is shared externally.

## Out of Scope

- Theoretical issues without a credible attack path on a managed endpoint
- Issues requiring physical device access with no MDM deployment context
- Best-practice suggestions without a concrete security impact — submit those as regular issues or pull requests

## Disclosure Policy

We request responsible disclosure: allow us reasonable time to investigate and remediate before public disclosure. We will credit reporters in release notes unless anonymity is requested.

## Engineering Security Standards

The security engineering standards that govern this repository are documented in [`SECURITY_PHILOSOPHY.md`](SECURITY_PHILOSOPHY.md).
