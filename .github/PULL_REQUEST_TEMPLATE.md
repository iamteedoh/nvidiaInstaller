<!--
  Thanks for contributing! Keep PRs focused and reference the issue they close.
  CI (Woodpecker) enforces repo compliance: license headers, LICENSE, and funding metadata.
-->

## What & why

<!-- What does this change and what problem does it solve? Link the issue: "Closes #123". -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature (new GPU/driver-stream/distro support, new flag)
- [ ] Refactor / cleanup
- [ ] Docs

## GPU / driver-stream impact

<!-- If this touches detection or package selection, which architectures/streams are affected?
     e.g. "adds 580xx for Maxwell/Pascal/Volta; current/470xx paths unchanged". -->

## Testing

<!-- How did you verify this? For detection logic, list the GPUs/codenames you checked and the resulting stream. -->

- [ ] `bash -n nvidia-installer.sh` passes
- [ ] `shellcheck nvidia-installer.sh` clean (or new findings explained)
- [ ] Manually exercised the affected path

## Checklist

- [ ] My change is scoped to one logical concern
- [ ] I updated the README / docs if behavior changed
- [ ] I did not commit secrets or machine-specific paths
