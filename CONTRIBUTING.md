# Contributing to nvidiaInstaller

Thanks for helping improve nvidiaInstaller. This guide covers local setup,
validation, and the pull request process.

## Ways to contribute

- **Report a bug** using the repository's bug report form. Driver selection is
  GPU-architecture-specific, so always include the output of
  `lspci -nn | grep -i nvidia` and your distro + version.
- **Request a feature** using the feature request form (new GPU/driver-stream
  support, a new distro, a flag, a UX tweak).
- **Ask a question** in [Discussions](https://github.com/iamteedoh/nvidiaInstaller/discussions),
  not the issue tracker.
- **Send a pull request** after opening an issue for non-trivial changes.
- **Report a vulnerability privately** by following [SECURITY.md](SECURITY.md).

## Issue workflow

Issues move through a small set of `status:` labels: `status:to-do` (triaged,
not started), `status:in-progress` (being worked on a branch),
`status:ready-for-test` (PR open, awaiting review), and `status:ready-to-ship`
(merged to `main`, queued for the next release). Type is tracked with
`type:bug`, `type:feature`, and `type:fix`. Comment on an issue before you
start so it isn't double-staffed.

## Prerequisites

- Bash 4 or newer
- ShellCheck
- gitleaks 8.30.1 or newer
- A Fedora- or Ubuntu-family VM with an NVIDIA GPU only when exercising the
  actual install paths (do not test installs on a machine you can't rebuild)

## Set up from a clean clone

```bash
git clone https://github.com/iamteedoh/nvidiaInstaller.git
cd nvidiaInstaller
chmod +x nvidia-installer.sh
```

There is no build step and no environment file. Never commit secrets, tokens,
or machine-specific paths.

## Run the validation suite

Run the same checks that protect `main`:

```bash
git ls-files '*.sh' | xargs shellcheck --severity=error
git ls-files '*.sh' | xargs -n1 bash -n
gitleaks git . --config .gitleaks.toml --redact --no-banner
```

## Coding standards

This is a single Bash script (`nvidia-installer.sh`). Match the existing style.

- **Header block.** Scripts carry an SPDX line
  (`# SPDX-License-Identifier: GPL-3.0-or-later`) within the first lines; new
  scripts also need the standard header
  (`## Author / ## Name of Program / ## Date Created / ## Description`).
- **Driver selection** is keyed off the GPU **architecture codename** from
  `lspci -nn` (e.g. `gp107` → Pascal → 580xx), not marketing names. If you add
  a GPU class, state which codenames/PCI IDs you matched and confirm you didn't
  pull a newer architecture into a legacy stream.

## Project layout

- `nvidia-installer.sh` — the entire tool: TUI helpers, system detection,
  driver-stream selection, and the Fedora/RPM and Ubuntu/DEB install paths
  (interactive and `-y` auto variants)
- `.github/workflows/` — source validation and source-only release automation
- `.github/ISSUE_TEMPLATE/` — bug report and feature request forms

## Pull request process

1. Create a branch from `main`.
2. Make the smallest complete change and update documentation.
3. Run the full validation suite above.
4. Use a [Conventional Commit](https://www.conventionalcommits.org/) PR title:
   `feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `test:`, or `chore:`.
5. Complete the pull request template and link the related public issue.
6. Wait for all required checks to pass, then squash-merge.

The PR title becomes the squash commit subject and drives release-please:
`fix:` creates a patch release, `feat:` creates a minor release, and a `!` or
`BREAKING CHANGE:` footer creates a breaking release.

## License

By contributing, you agree that your contributions are licensed under the
project's [GNU General Public License v3](LICENSE).
