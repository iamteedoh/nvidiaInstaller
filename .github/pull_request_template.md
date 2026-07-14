<!-- Thanks for contributing to nvidiaInstaller! -->

## What does this PR do?

<!-- Briefly describe the change and why it is needed. -->

## Related issue

<!-- Link the public issue this addresses, for example: Closes #123. -->

## GPU / driver-stream impact

<!-- If this touches detection or package selection, which architectures/streams are affected?
     e.g. "adds 580xx for Maxwell/Pascal/Volta; current/470xx paths unchanged". -->

## Validation

<!-- List the commands and manual checks you ran. For detection logic, list the
     GPUs/codenames you checked and the resulting stream. -->

## Checklist

- [ ] `git ls-files '*.sh' | xargs shellcheck --severity=error` passes
- [ ] `git ls-files '*.sh' | xargs -n1 bash -n` passes
- [ ] gitleaks reports no secrets in Git history
- [ ] Scripts and programs include a GPL-3.0-or-later SPDX header
- [ ] No secrets, tokens, credentials, or machine-specific paths are committed
- [ ] Documentation is updated for user-visible or operational changes
- [ ] The PR title follows Conventional Commits
