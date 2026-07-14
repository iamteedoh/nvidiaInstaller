# Security Policy

## Reporting a vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Use GitHub's private vulnerability reporting instead:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Provide the details requested below.

If private reporting is unavailable, contact the maintainer through the
[iamteedoh GitHub profile](https://github.com/iamteedoh).

## What to include

- A description of the issue and its potential impact (e.g. privilege
  escalation, arbitrary command execution, untrusted download)
- Reproduction steps or a minimal proof of concept
- The affected release, commit, distro, and GPU/driver stream
- A suggested remediation, if known

Never include passwords, private hostnames, or unredacted logs in a report.

## Security-sensitive areas

nvidiaInstaller runs as root and modifies system configuration, so the most
sensitive surfaces are:

- The package sources it trusts: the RPM Fusion release RPMs it installs
  (fetched over HTTPS with `--nogpgcheck`), the RPM Fusion driver packages,
  and the driver `ubuntu-drivers` recommends
- Everything executed as root: `dnf`/`apt` installs, `dracut --force`,
  `update-initramfs -u`, and `reboot`
- Any path where untrusted input (`lspci` output, `/etc/os-release`,
  package-manager output) could influence a command
- Boot-critical changes: `/etc/dracut.conf.d/nvidia.conf`, initramfs
  regeneration, and the Secure Boot / MOK enrollment guidance

## Supported versions

Security fixes land on `main` and ship in the next tagged source release. Test
against the latest release or `main` before reporting an issue.
