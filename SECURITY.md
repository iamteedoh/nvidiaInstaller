# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

This project installs proprietary drivers as root and modifies system
configuration, so security reports are taken seriously. Report privately via one
of:

- **GitHub Security Advisories** (preferred): open a private report at
  <https://github.com/iamteedoh/nvidiaInstaller/security/advisories/new>.
- **Email**: gvalentin04@gmail.com with `[SECURITY] nvidiaInstaller` in the subject.

Please include:

- The version / commit you tested.
- A description of the issue and its impact (e.g. privilege escalation,
  arbitrary command execution, untrusted download).
- Steps to reproduce, and a proof of concept if you have one.

## What to expect

- An acknowledgement within a few days.
- An assessment and, if confirmed, a fix coordinated with you before public
  disclosure.
- Credit in the release notes if you'd like it.

## Scope

Because this is an installer that runs with elevated privileges, the areas of
highest interest are: the package sources it trusts (RPM Fusion repos, release
RPMs, download URLs), anything executed as root, and any path where untrusted
input could influence a command. Reports in these areas are especially welcome.

## Supported versions

Fixes are made against the latest `main`. There is no long-term support branch;
please test against `main` before reporting.
