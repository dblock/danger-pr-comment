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

Do not manually date the changelog or update workflow tag references. The release workflow runs `ruby scripts/release_version.rb prepare`, which dates the current version's changelog section using the UTC date, adds a fresh empty `[Unreleased]` section, and updates the README, installer, and matching installer specs to `@vVERSION`. It validates all these files before writing them and can be rerun for an already prepared release without changing its date or duplicating its heading.

## Publish

Run the [Release workflow](https://github.com/numbata/danger-pr-comment/actions/workflows/release.yml) on `main`, or use:

```sh
gh workflow run release.yml --ref main
```

Approve the `release` environment deployment if required. The workflow rejects stale dispatches and existing tags, validates the version, prepares the release files, and runs the full specs and RuboCop against those prepared files. It commits and pushes preparation to `main` before building and tagging that exact commit. A concurrent push to `main` stops the release rather than overwriting it.

It then builds the gem, authenticates through OIDC, publishes the gem, pushes the release tag, and creates a GitHub release with the gem attached. Finally, it increments only the gem's patch version and pushes that change to `main`; the README and installer continue referencing the published release. Release runs are serialized; failures stop subsequent steps.

The installer is downloaded from `main`, so there is a short window between pushing preparation and pushing the release tag when its new workflow references do not resolve. If publication fails, resolve the failure promptly using the recovery steps below.

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

* Before publication: fix the failure and dispatch a new run. Preparation may already be committed to `main`; the helper preserves that release section and date on retry. If new unreleased changes were added after preparation, reconcile those notes with the prepared release section before retrying. If an upload failed or timed out, check RubyGems first; the server may have accepted it.
* Gem published, tag missing: recover the original run's commit, create `vVERSION` at that exact commit, and push it. Do not tag the latest `main` unless it is that commit.
* Tag pushed, GitHub release missing: create the release from the existing tag using `gh release create vVERSION --verify-tag --generate-notes`, attaching the original built gem if available.
* Release complete, version bump failed: pull current `main`, resolve the branch permission or concurrent-push problem, and update the version only if it still equals the released version. Run `ruby scripts/release_version.rb bump`, review the diff, commit, and push.

Do not rerun the entire workflow after publication to repair a missing tag, release, or version bump. Complete only the missing steps.

## Manual publishing

Trusted publishing authenticates GitHub Actions, not a local shell. For a manual release, authenticate locally using your RubyGems account and complete MFA when prompted. Starting from clean, current `main` with the intended version (0.2.0 in this example), prepare and validate the files before committing, building, and tagging:

```sh
ruby scripts/release_version.rb prepare
bundle exec rake
git add CHANGELOG.md README.md scripts/install-workflows.sh spec/scripts/install_workflows_spec.rb
git diff --cached --quiet || git commit -m "Prepare release 0.2.0"
git push origin main
gem build danger-pr-comment.gemspec
gem push danger-pr-comment-0.2.0.gem
git tag v0.2.0
git push origin v0.2.0
gh release create v0.2.0 --verify-tag --generate-notes danger-pr-comment-0.2.0.gem
ruby scripts/release_version.rb bump
git add lib/danger-pr-comment/version.rb
git commit -m "Prepare next development version"
git push origin main
```

Verify publication as above. Never commit credentials or OTP codes.
