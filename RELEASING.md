# Releasing

## One-time setup

Publishing uses [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) through GitHub Actions OIDC. No stored RubyGems API key or manual OTP is required.

1. In the GitHub repository settings, create an environment named `release`. Restrict deployments to `main` and configure required reviewers where available.
2. As a gem owner, open the gem's **Trusted publishers** page on RubyGems.org and add a GitHub Actions publisher with repository owner `numbata`, repository name `danger-pr-comment`, workflow filename `release.yml`, and environment `release`. Use the actual owner and repository if publishing from another repository; forks are not automatically trusted.
3. Ensure branch rules allow the Actions bot to push the next development version directly to `main`.

The job grants `id-token: write` and uses the pinned official `rubygems/configure-rubygems-credentials` action to exchange GitHub's identity for short-lived publishing credentials. It then uploads the already-built gem with `gem push`. Keeping authentication separate from `rubygems/release-gem` preserves this workflow's publish-before-tag order.

After verifying trusted publishing works, remove any obsolete `RUBYGEMS_API_KEY` repository secret and revoke its RubyGems API key if it is no longer used elsewhere.

## Prepare

Start from current `main`, review changes since the last release, and ensure project tests pass. Set `lib/danger-pr-comment/version.rb` to the intended MAJOR.MINOR.PATCH version. For a minor or major release, replace the automatically prepared patch version before committing.

Before committing the release preparation:

1. Rename the `## [Unreleased]` changelog heading to `## [VERSION] - YYYY-MM-DD`, using the release version and date, and add a fresh empty `## [Unreleased]` section above it.
2. Update the reusable workflow references in both `README.md` and `scripts/install-workflows.sh` to `@vVERSION` for the release being prepared. The installer is downloaded from `main`, so leaving old references would keep installing workflows from the previous release. Keep these references at the latest release when bumping the next development version.
3. Update the expected workflow references in `spec/scripts/install_workflows_spec.rb` to the same release tag.

For example, after preparing the files for 0.2.0:

```sh
git checkout main
git pull --ff-only origin main
bundle exec rake
git add lib/danger-pr-comment/version.rb CHANGELOG.md README.md scripts/install-workflows.sh spec/scripts/install_workflows_spec.rb
git commit -m "Prepare release 0.2.0"
git push origin main
```

## Publish

Run the [Release workflow](https://github.com/numbata/danger-pr-comment/actions/workflows/release.yml) on `main`, or use:

```sh
gh workflow run release.yml --ref main
```

Approve the `release` environment deployment if required. The workflow rejects stale release commits and existing tags, runs the full specs and RuboCop (including the release helper specs) against the exact release commit, validates the version, builds the gem, authenticates through OIDC, publishes the gem, pushes the release tag, and creates a GitHub release with the gem attached. It then increments the patch version and pushes that change to `main`. Release runs are serialized; failures stop subsequent steps.

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

* Before publication: fix the failure and dispatch a new run. If an upload failed or timed out, check RubyGems first; the server may have accepted it.
* Gem published, tag missing: recover the original run's commit, create `vVERSION` at that exact commit, and push it. Do not tag the latest `main` unless it is that commit.
* Tag pushed, GitHub release missing: create the release from the existing tag using `gh release create vVERSION --verify-tag --generate-notes`, attaching the original built gem if available.
* Release complete, version bump failed: pull current `main`, resolve the branch permission or concurrent-push problem, and update the version only if it still equals the released version. Run `ruby scripts/release_version.rb bump`, review the diff, commit, and push.

Do not rerun the entire workflow after publication to repair a missing tag, release, or version bump. Complete only the missing steps.

## Manual publishing

Trusted publishing authenticates GitHub Actions, not a local shell. For a manual release, authenticate locally using your RubyGems account and complete MFA when prompted. From the clean, tested release commit, run the equivalent steps:

```sh
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
