---
name: release
description: 'Release workflow for omakvn: bump the manifest version, validate the Omarchy plugin, commit, tag, optionally push, and open a prefilled marketplace verification form. Use for preparing a release, releasing an explicit version, or bumping the major, minor, or patch version.'
---

# Release omakvn

Create a local release first. Pushing is a separate, explicitly confirmed step.

## Determine the version

1. Read `version` from `manifest.json`. Accept only stable semantic versions in `MAJOR.MINOR.PATCH` form, with non-negative integer components and no prefixes or prerelease/build suffixes.
2. Determine the target version from the request:
   - `patch`: increment patch.
   - `minor`: increment minor and reset patch to zero.
   - `major`: increment major and reset minor and patch to zero.
   - An explicit `X.Y.Z`: use it as written.
3. Stop if the target version equals the current version, is lower than it, or is otherwise invalid. Do not silently choose another version.

## Preflight

Before editing anything:

1. Require a clean working tree, including no staged, unstaged, or untracked changes. If it is dirty, report the paths and stop without modifying them.
2. Record the current branch and require an `origin` remote.
3. Set the tag name to `vX.Y.Z`. Stop if that tag already exists locally or if `refs/tags/vX.Y.Z` exists on `origin`.

## Prepare the release

1. Change only the top-level `version` field in `manifest.json`, preserving its formatting and every other field.
2. Run all release checks from the repository root, in this order:

   ```sh
   omarchy plugin validate .
   qmllint -I /usr/share/omarchy/shell Widget.qml KvnService.qml
   ```

   If a listed command is unavailable, stop and report it rather than silently skipping the check.
3. Stop on the first failed check. Leave the version edit uncommitted and report the failure; do not create a commit or tag.
4. Verify that the diff contains only the intended `manifest.json` version change.
5. Stage only `manifest.json` and commit it:

   ```sh
   git add manifest.json
   git commit -m "chore(release): bump version to X.Y.Z"
   ```

6. Create an annotated tag on that commit:

   ```sh
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```

7. Verify that the tag resolves to the new commit, then report the version, full commit SHA, tag, and completed checks.

If the commit succeeds but tag creation fails, stop and report that exact partial state. Do not amend, reset, delete, or recreate release objects without a new user instruction.

## Confirm and push

Ask whether to push the release commit and tag. Do not push before the user explicitly agrees.

If the user declines, finish with the local commit and tag intact. If the user agrees:

1. Push the recorded branch to `origin`.
2. Push only `refs/tags/vX.Y.Z` to `origin`.
3. Verify that both pushes succeeded. If either fails, report which refs reached `origin` and stop; do not open the verification form until both refs are present remotely.

## Open marketplace verification

After both pushes succeed, build this URL with every query value percent-encoded:

```text
https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml&title=[Verify]: NAME vX.Y.Z&plugin-id=PLUGIN_ID&repository=REPOSITORY_URL&target-commit=FULL_SHA
```

Populate it as follows:

- `title`: `[Verify]: NAME vX.Y.Z`, using `name` from `manifest.json`.
- `plugin-id`: `id` from `manifest.json`.
- `repository`: the `origin` URL normalized to its public HTTPS repository URL without a trailing `.git`. For this repository, the configured remote is `https://github.com/yarikov/omakvn`.
- `target-commit`: the full 40-character SHA of the tagged release commit.

GitHub URL query parameters prefill text inputs but do not select issue-form dropdown values. Do not add `verification-action` to the URL.

After opening the form, tell the user to select `Verify and publish a newer upstream commit` manually. Also leave `acknowledgment` and `standard-installation-acknowledgment` for manual review; they are attestations and must not be pre-checked.

Open the encoded URL with `xdg-open`, then always return the same URL as a clickable Markdown link. If `xdg-open` fails, report the failure but still provide the link. Opening the form does not authorize submitting the issue; leave submission to the user.
