# Contributing to nvidiaInstaller

Thanks for your interest in improving this project! This document explains how
work flows from an idea or bug report through to a merged change.

## Ways to contribute

- **Report a bug** — open an issue with the **Bug report** form. Driver
  selection is GPU-architecture-specific, so always include the output of
  `lspci -nn | grep -i nvidia` and your distro + version.
- **Request a feature** — use the **Feature request** form (new GPU/driver-stream
  support, a new distro, a flag, a UX tweak).
- **Ask a question** — use [Discussions](https://github.com/iamteedoh/nvidiaInstaller/discussions),
  not the issue tracker.
- **Report a vulnerability** — privately, per [SECURITY.md](SECURITY.md). Never in a public issue.

## Issue & PR lifecycle

Issues move through a small set of `status:` labels that mirror the project's
shipping workflow:

| Label | Meaning |
|---|---|
| `status:to-do` | Triaged and accepted, not started. |
| `status:in-progress` | Someone is actively working it on a branch. |
| `status:ready-for-test` | PR open, awaiting review / hands-on testing. |
| `status:ready-to-ship` | Approved and merged to `main`, queued for the next release tag. |

Type is tracked with `type:bug`, `type:feature`, and `type:fix`. Newcomer-friendly
work is marked `good first issue` / `help wanted`.

## Making a change

1. **Comment on the issue** you intend to work so it can be moved to
   `status:in-progress` and isn't double-staffed. (No issue yet? Open one first
   so the change is tracked.)
2. **Fork & branch.** Branch names are `<issue-number>-short-slug`,
   e.g. `42-maxwell-580xx`.
3. **Keep the change focused** — one logical concern per PR.
4. **Open a PR** against `main` using the PR template, with `Closes #<n>`.

## Coding standards

This is a single Bash script (`nvidia-installer.sh`). Match the existing style.

- **Header block.** Scripts must carry the standard header (see the top of the
  existing script). CI compliance fails without it:
  ```
  ## Author: <your name>
  ## Name of Program: <name>
  ## Date Created: <YYYY-MM-DD>
  ## Description: <short description>
  ```
- **Lint clean.** `bash -n nvidia-installer.sh` must pass, and
  `shellcheck nvidia-installer.sh` should be clean (explain any unavoidable findings).
- **Driver selection** is keyed off the GPU **architecture codename** from
  `lspci -nn` (e.g. `gp107` → Pascal → 580xx), not marketing names. If you add a
  GPU class, state which codenames/PCI IDs you matched and confirm you didn't
  pull a newer architecture into a legacy stream.
- **No secrets, no machine-specific paths.**

## CI / compliance

Pushes and PRs are checked by the project's Woodpecker pipeline, which enforces
repository compliance — a valid `LICENSE`, sponsorship/funding metadata
(`.github/FUNDING.yml`), and required file headers. Keep these intact.

## License

By contributing, you agree your contributions are licensed under the repository's
[GNU GPL v3.0](LICENSE).
