# Releasing

## One-time setup

Publishing uses [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) through GitHub Actions OIDC. No stored RubyGems API key or manual OTP is required.

1. In the GitHub repository settings, create an environment named `release`. Restrict deployments to `main` and configure required reviewers where available.
2. As a gem owner, open the gem's **Trusted publishers** page on RubyGems.org and add a GitHub Actions publisher with repository owner `numbata`, repository name `danger-pr-comment`, workflow filename `release.yml`, and environment `release`. Use the actual owner and repository if publishing from another repository; forks are not automatically trusted.
3. Ensure branch rules allow the Actions bot to push release preparation and the next development version directly to `main`.

The job grants `id-token: write` and uses the pinned official `rubygems/configure-rubygems-credentials` action to exchange GitHub's identity for short-lived publishing credentials. It then uploads the already-built gem with `gem push`. Keeping authentication separate from `rubygems/release-gem` preserves this workflow's publish-before-tag order.

After verifying trusted publishing works, remove any obsolete `RUBYGEMS_API_KEY` repository secret and revoke its RubyGems API key if it is no longer used elsewhere.

## Prepare

Start from current `main`, review changes since the last release, and maintain the release notes under `## [Unreleased]` in `CHANGELOG.md`. The previous release has already incremented `lib/danger-pr-comment/version.rb` to the next patch version, so a normal patch release needs no manual version change.

For a minor or major release, change `lib/danger-pr-comment/version.rb` to the intended MAJOR.MINOR.PATCH version, commit, and push before dispatching the workflow.

Do not manually date the changelog or update workflow tag references. The release workflow runs `ruby scripts/release_version.rb prepare`, which dates the current version's changelog section using the UTC date, adds a fresh empty `[Unreleased]` section, and updates the README, installer, and matching installer specs to `@vVERSION`. It rejects empty release notes and validates all these files before writing them. It can be rerun for an already prepared release without changing its date or duplicating its heading.

## Publish

Run the [Release workflow](https://github.com/numbata/danger-pr-comment/actions/workflows/release.yml) on `main`, or use:

```sh
gh workflow run release.yml --ref main
```

Approve the `release` environment deployment if required. The workflow rejects stale dispatches and existing tags, validates the version, prepares the release files, and runs the full specs and RuboCop against those prepared files. It commits preparation locally, then builds and tags that exact commit. Before publication, it uploads the built gem and a Git bundle containing the prepared commit and tag as a `release-vVERSION` recovery artifact.

It authenticates through OIDC, publishes the gem, and atomically pushes the prepared commit to `main` together with the release tag using `git push --atomic origin HEAD:main "v$VERSION"`. A concurrent push to `main` rejects both ref updates rather than overwriting it. It then creates a GitHub release with the gem attached. Finally, it increments only the gem's patch version and pushes that change to `main`; the README and installer continue referencing the published release. Release runs are serialized; failures stop subsequent steps.

The installer is downloaded from `main`. Publishing the gem first and updating `main` and the tag atomically keeps its workflow references on an existing tag; a publication failure leaves both GitHub refs unchanged.

The automatic `GITHUB_TOKEN` is sufficient for GitHub operations, but its pushes do not trigger other push-based workflows. Run required checks explicitly rather than relying on tag or version-bump pushes to trigger CI.

## Verify

Check the exact published version, release tag, GitHub release, and next development version:

```sh
curl --fail https://rubygems.org/api/v2/rubygems/danger-pr-comment/versions/0.2.0.json
git ls-remote --tags origin 'v0.2.0*'
gh release view v0.2.0
git pull --ff-only origin main
cat lib/danger-pr-comment/version.rb
```

## Recover from a failed release

Check which steps succeeded before retrying. RubyGems versions cannot be overwritten, and published tags must not be moved.

If OIDC authentication fails, check that the configured publisher's owner, repository, workflow filename, and environment match the workflow exactly, and that `id-token: write` is enabled. Do not add a long-lived API key as a workaround.

* Before publication: fix the failure and dispatch a new run; automated preparation has not changed `main` or pushed a tag. The helper also preserves a release section and date prepared manually. If an upload failed or timed out, check RubyGems first; the server may have accepted it.
* Gem published, atomic push failed: download the original run's `release-vVERSION` artifact with `gh run download RUN_ID --name release-vVERSION`. Verify its gem against RubyGems, then recover the exact prepared tag and commit with `git fetch ./release.bundle refs/tags/vVERSION:refs/tags/vVERSION`. Push the recovered release commit and tag atomically if `main` has not advanced. Otherwise preserve the newer commits and reconcile release preparation before retrying the ref updates; never force-push `main` or move the release tag. Do not prepare a different commit and tag it as the already published gem.
* Tag pushed, GitHub release missing: create the release from the existing tag using `gh release create vVERSION --verify-tag --generate-notes`, attaching the original built gem if available.
* Release complete, version bump failed: pull current `main`, resolve the branch permission or concurrent-push problem, and update the version only if it still equals the released version. Run `ruby scripts/release_version.rb bump`, review the diff, commit, and push.

Do not rerun the entire workflow after publication to repair a missing tag, release, or version bump. Complete only the missing steps.

## Manual publishing

Trusted publishing authenticates GitHub Actions, not a local shell. For a manual release, authenticate locally using your RubyGems account and complete MFA when prompted. Starting from clean, current `main` with the intended version (0.2.0 in this example), prepare and validate the files before committing, building, and tagging:

```sh
ruby scripts/release_version.rb prepare
bundle exec rake
git add -u
git diff --cached --quiet || git commit -m "Prepare release 0.2.0"
gem build danger-pr-comment.gemspec
gem push danger-pr-comment-0.2.0.gem
git tag v0.2.0
git push --atomic origin HEAD:main v0.2.0
gh release create v0.2.0 --verify-tag --generate-notes danger-pr-comment-0.2.0.gem
ruby scripts/release_version.rb bump
git add lib/danger-pr-comment/version.rb
git commit -m "Prepare next development version"
git push origin main
```

Verify publication as above. Never commit credentials or OTP codes.
