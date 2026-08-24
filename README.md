# Flutter App Template

[![codecov](https://codecov.io/github/ekawijayasusilo/flutter_app_template/graph/badge.svg)](https://app.codecov.io/github/ekawijayasusilo/flutter_app_template)
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A starting point for new Flutter projects, with CI, quality gates and safeguards already wired up.

This is **not an application**. It is the scaffolding an application starts from: a Dart pub
workspace, a design system package with a Widgetbook catalog, a single gated CI workflow,
dependency-vulnerability and secret scanning, Codecov-enforced coverage, automated dependency
updates, and shared fastlane lanes. The only app code is the counter sample from
[Very Good CLI][very_good_cli_link].

---

## Use this template

Create a repository from this template, then run the setup wizard from
[`shared_scripts`][shared_scripts_link]. Fetch it to disk, **read it**, then run it:

```sh
curl -fsSL -o setup-repo.sh \
  https://raw.githubusercontent.com/ekawijayasusilo/shared_scripts/v1.1.1/scripts/setup-repo.sh
less setup-repo.sh
bash setup-repo.sh
```

Not `curl | bash`. The script handles a GitHub App private key and API tokens, so it must be
reviewable before it executes. Tags are mutable — substitute a full commit SHA in that URL when you
want true immutability.

It needs an authenticated [`gh`](https://cli.github.com) and bash 4+ (macOS ships bash 3.2, so
`brew install bash`).

**The wizard runs in two phases**, because branch-protection required-check *names* do not exist
until the workflows have run at least once:

1. **Phase 1** — confirm the target repo, verify the GitHub App, Codecov, `OPENCODE_API_KEY`,
   optional `OCR_LLM_URL` / `OCR_LLM_MODEL`, enable Issues, auto-merge and Actions write
   permissions. Then it stops and tells you to open a PR.
2. **Phase 2** — after the first green run, re-run it. It discovers the actual check names and
   configures branch protection from them.

Phase is detected from live GitHub state, not a local file, so re-running is always safe.

### Manual fallback

If you would rather not run the wizard:

- **Settings → Actions → General → Workflow permissions → Read and write.** This is a hard cap on
  what any workflow's `permissions:` block can request.
- **Secrets:** `CODECOV_TOKEN` (coverage upload), `OPENCODE_API_KEY` (the three assistant
  workflows). `GITHUB_TOKEN` is automatic — never set it.
- **Optional variables:** `OCR_LLM_URL`, `OCR_LLM_MODEL` to override the review model per repo.
- **Install the Codecov GitHub App** and grant it access to the repository.
- **Branch protection on `main`:** require the `ci-status` check. That single fan-in gate covers
  every job in `ci.yaml`, so you do not list them individually. Add the `codecov/*` contexts you
  want as well — check which ones actually post first, because requiring a context that never
  arrives blocks every PR forever.
- **`GITLEAKS_LICENSE`** is required only if the repository is owned by an **organization**.
  Personal-account repositories need no key.

---

## Repository layout

A Dart **pub workspace**: one root `pubspec.lock`, one resolve, one shared
`.dart_tool/package_config.json`.

```
flutter_app_template/          # the app itself
├── lib/, test/
└── packages/
    └── design_system/         # shared widgets, theme, spacing, text styles
        └── widgetbook/        # widgetbook_catalog — visual catalog for design_system
```

| Package | Purpose | Tests |
| --- | --- | --- |
| `flutter_app_template` | The application | 8 |
| `design_system` | Widgets, theme and tokens, consumed via a barrel export | 65 |
| `widgetbook_catalog` | Visual catalog for `design_system`. Never published, never shipped | none, by design |

Each member declares `resolution: workspace`. Because the workspace shares one package config, a
dev dependency declared once at the root is runnable from every member directory — which is why
`dart_code_linter` appears only in the root `pubspec.yaml`.

`lib/` must import `design_system` through its barrel export, never `package:design_system/src/...`.
That is enforced, not merely documented — see [Linting](#linting).

---

## CI and quality gates

Everything that can block a merge lives in a single workflow, [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml),
gated by one fan-in job.

### On every pull request

| Job | What it does |
| --- | --- |
| `changes` | Detects whether dependency files were touched, to gate `license-check` |
| `flutter` | Format, analyze, bloc lint, and **all 73 tests across all three packages**, then per-package Codecov upload and Test Analytics |
| `license-check` | Rejects dependency licenses outside `MIT, BSD-3-Clause, BSD-2-Clause, Apache-2.0` |
| `spell-check` | cspell over `**/*.md` |
| `semantic-pull-request` | Enforces a Conventional Commits PR title |
| `osv-scanner-pr` | Dependency vulnerability scan (SCA) |
| `gitleaks` | Secret scan of the PR's commit range |
| `dart-code-linter` | Metrics, unused-code detection and extra lint rules, per package |
| `fastlane-lanes` | Proves the pinned fastlane import still resolves |
| **`ci-status`** | **The fan-in gate — the only check branch protection needs** |

### On a schedule

[`security_scheduled.yaml`](.github/workflows/security_scheduled.yaml) runs `osv-scanner` **weekly**
and a **monthly** full-history `gitleaks` sweep. The monthly run re-tests immutable history against
updated detection rules — that is its entire purpose.

Renovate runs daily, centrally, from `shared_workflow`. Nothing is scheduled here for it.

> GitHub disables `schedule` triggers on repositories with 60 days of no activity. On a template
> that sits idle, both sweeps stop silently until someone re-enables them.

### Advisory, never blocking

`ocr-review` and `opencode-simplify` review pull requests and post comments. `opencode` responds to
`/oc` or `/opencode` in a comment. All three are LLM-driven and must never be required checks.

`opencode` additionally requires the commenter to be the repository **owner or a collaborator**.
Without that check any GitHub user could drive an agent holding `contents: write` and the API key,
because `issue_comment` runs on the default branch with full secrets. The Actions setting that
requires approval for fork pull request workflows does not cover this — it gates fork PR runs only.

### Why one workflow file, and why the gate looks like that

`needs:` cannot reference a job in another workflow file, so a fan-in gate is only possible within a
single file. Hence one `ci.yaml`.

There is deliberately no `on.pull_request.paths` filter. GitHub leaves a required check that was
skipped by path filtering in a permanent *Pending* state, which would block every PR that does not
touch those paths. Path filtering happens per job instead, via `changes`.

The gate uses `if: always()` and fails if any dependency reports `failure` or `cancelled`. Without
`always()`, a failing dependency makes the gate **skipped** — and GitHub reports a skipped job as
**Success**. That is a required check that silently passes while the build is broken. Legitimate
skips are tolerated, because the jobs that skip are path-gated or event-gated, and a job skipped
because an upstream failed cannot slip through: the upstream itself reports `failure`.

---

## Security tooling

Two scanners, and it is worth being precise about what they are:

| Tool | Category | On PR | Scheduled |
| --- | --- | --- | --- |
| [osv-scanner](https://google.github.io/osv-scanner/) | **SCA** — known vulnerabilities in dependencies | blocking | weekly |
| [gitleaks](https://github.com/gitleaks/gitleaks) | **Secret scanning** | blocking (incremental) | monthly (full history) |

**Neither is SAST, and there is deliberately no SAST here.** Semgrep parses Dart but ships a
near-empty Dart/Flutter ruleset, so adding it would be theatre.

**The job failing is the gate. SARIF and the Security tab are a bonus.** `osv-scanner` runs with
`upload-sarif: false`, because the upstream SARIF upload step has no `continue-on-error` and returns
403 on a repository without Code Security — so on a private repo scaffolded from this template, a
SARIF upload would turn a passing scan into a failing job. The SARIF is still kept as a workflow
artifact. Losing the Security tab is accepted; losing the gate is not.

`gitleaks` never uploads to Code Scanning at all — it only attaches its SARIF as an artifact. That
is why its job requests `pull-requests: write` rather than `security-events: write`.

### Suppressing a finding

[`.gitleaks.toml`](.gitleaks.toml) ships an allowlist for Firebase config files — **present but
commented out**. Firebase is not in this template yet, and `google-services.json` /
`firebase_options.dart` keys are public by design: they identify a project, they do not authorize
access. Security lives in Firebase Security Rules and App Check. The trap is documented before it is
hit.

[`osv-scanner.toml`](osv-scanner.toml) holds vulnerability exceptions. Every entry needs an
`ignoreUntil` expiry and a reason explaining why it is acceptable **and** what would let you remove
it, so exceptions expire on their own instead of becoming permanent. There is currently one, for a
transitive fastlane dependency — see [fastlane](#fastlane).

---

## Coverage

Codecov is the authority, not `very_good test --min-coverage`. The workflow's local minimum is
**0** on purpose: only Codecov can express **patch** coverage — how well the lines a PR actually
touched are covered — separately from project coverage.

Both targets are **75%**, configured in [`codecov.yml`](codecov.yml), with one flag per package.

Flag names are not arbitrary: the reusable workflow derives one per package from that package's
`name:` in `pubspec.yaml`. So they are `flutter_app_template` and `design_system`.
`widgetbook_catalog` has no tests, so no report and no flag.

Both flags set `carryforward: true`, which keeps a flag's last known coverage when a run uploads no
report for it — without it those files would report 0%.

Test Analytics is uploaded too, but is **non-blocking end to end**. It depends on
`package:junitreport`, which is old and third-party, so a break there degrades to "no test
analytics", never a red build.

---

## Linting

Three layers, deliberately not overlapping:

| Layer | How it runs | Covers |
| --- | --- | --- |
| [`very_good_analysis`](https://pub.dev/packages/very_good_analysis) | Dart analyzer | Baseline style and correctness |
| [`bloc_lint`](https://pub.dev/packages/bloc_lint) | Analyzer plugin, via `custom_lint` | Bloc-specific best practice |
| [`dart_code_linter`](https://pub.dev/packages/dart_code_linter) | **CLI only** | Metrics, unused code, Flutter perf rules |

`dart_code_linter` is CLI-only by necessity: `bloc_lint` already occupies the analyzer plugin slot
via `custom_lint`, and registering both would conflict. The `dart_code_linter:` block in
`analysis_options.yaml` is still read by the CLI without plugin registration.

**Metric thresholds** (currently with plenty of headroom — the repo's real maxima are 8, 3 and 2):

| Metric | Threshold |
| --- | --- |
| `cyclomatic-complexity` | 20 |
| `number-of-parameters` | 8 |
| `maximum-nesting-level` | 5 |

`number-of-parameters` is 8 rather than the default 4 because Flutter widget constructors routinely
exceed 4 — `AppButton` already takes 5.

Beyond the analyzer, it also runs `check-unused-code` and `check-unused-files`, which the Dart
analyzer structurally cannot do. `check-unused-l10n` runs advisory-only: Flutter's generated
`AppLocalizations` always reports `localeName` and `delegate` as unused, so a fatal run could never
pass.

**Architecture enforcement.** `avoid-banned-imports` blocks `lib/**` from importing
`package:design_system/src/**`, forcing use of the barrel export. Note its `paths` are **regexes,
not globs**, and they match the absolute OS path — hence `lib[/\\].*\.dart`, which works on both
path separators.

Rule names are **kebab-case** (`avoid-banned-imports`), not snake_case. A snake_case rule name is
silently ignored.

If you add rules, run them per package before trusting a green result. Each package has its own
`analysis_options.yaml`, so a rule added only at the root does not apply to `design_system` or
`widgetbook`.

---

## Dependency updates

[Renovate](https://docs.renovatebot.com), configured in [`renovate.json`](renovate.json), extending
modular presets from `shared_workflow` at an exact tag.

The runner is **central** — `shared_workflow` runs Renovate with autodiscover and processes only
repositories that commit a Renovate config. Committing `renovate.json` is the entire opt-in; there
is no runner workflow here.

Pub dependencies are **pinned to exact versions** rather than caret ranges. That is deliberate:
Renovate cannot regenerate a pub workspace's single root `pubspec.lock` for member-package updates
([renovate#40361](https://github.com/renovatebot/renovate/issues/40361), closed as not-planned).
With caret ranges a bumped constraint is often still satisfied by the locked version, so the PR
looks like an upgrade while CI tests the old code. Exact pins force a real re-resolve.

SDK constraints in `environment:` keep their ranges — pinning those would be wrong.

> **Known gap:** the Flutter customManager matches `flutter_version` but not `flutter-version`, so
> the `subosito/flutter-action` pin in the `dart-code-linter` job is not bumped automatically.
> Check it by hand when Flutter moves, until the shared preset is fixed.

---

## Fastlane

Lanes are shared from [`shared_scripts`][shared_scripts_link] and imported at an exact tag in
[`fastlane/Fastfile`](fastlane/Fastfile). They are **developer-local** — CI does not invoke them,
because `flutter` already covers format, analyze and test. CI only runs `fastlane lanes` to prove
the pinned import still resolves.

```sh
bundle install
bundle exec fastlane flutter <lane>
```

| Lane | Does |
| --- | --- |
| `clean_gen` | `flutter clean` per package, one root `pub get`, then `build_runner` where declared |
| `test` | `very_good test --recursive --coverage`. Optional `min_coverage:` |
| `analyze` | Format check, `flutter analyze`, `bloc lint`, `dart_code_linter` — all packages |
| `l10n` | `flutter gen-l10n` |
| `build_apk` / `build_aab` | Release Android builds. Optional `flavor:` |
| `build_ipa` | Unsigned iOS archive — produces `Runner.xcarchive`, not an `.ipa`. macOS only |
| `widgetbook` | Regenerates and runs the Widgetbook catalog on Chrome |

**Prerequisites:** `dart pub global activate very_good_cli`, `dart pub global activate bloc_tools`.
`dart_code_linter` is already a root dev dependency.

**Signing is out of scope.** `build_apk` and `build_aab` produce artifacts signed with the *debug*
keystore — Android has no unsigned build mode — so they are not release-installable.

> **Ruby caveat.** `Gemfile.lock` pins fastlane 2.234.0 because the reference toolchain is Ruby
> 2.7.5, and fastlane 2.235.0+ requires Ruby >= 3.0. Two consequences: the CI runner is pinned to
> Ruby 3.1 (a gem in this lock requires `ruby < 3.2`), and one transitive advisory in `excon` is
> unfixable at this fastlane version, so it carries a dated exception in `osv-scanner.toml`.
> Upgrading to Ruby 3.x and regenerating the lock at fastlane 2.238.0+ removes all three at once.
> Ruby 2.7 has been end-of-life since 2023.

---

## Flavors

Three flavors: `development`, `staging`, `production`.

```sh
flutter run --flavor development --target lib/main_development.dart
flutter run --flavor staging     --target lib/main_staging.dart
flutter run --flavor production  --target lib/main_production.dart
```

---

## Working with translations

Uses the [official internationalization guide][internationalization_link] with
[ARB files][arb_documentation_link].

**Add a string** — add a key to `lib/l10n/arb/app_en.arb`:

```arb
{
    "@@locale": "en",
    "helloWorld": "Hello World",
    "@helloWorld": {
        "description": "Hello World greeting."
    }
}
```

Then use it:

```dart
import 'package:flutter_app_template/l10n/l10n.dart';

@override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  return Text(l10n.helloWorld);
}
```

**Add a locale** — add an ARB file under `lib/l10n/arb/`, and add the locale to
`CFBundleLocalizations` in `ios/Runner/Info.plist`.

**Regenerate** with `flutter gen-l10n`, or just `flutter run`, which does it automatically.
Generated files carry `// coverage:ignore-file` and `// dart format off` headers, so they are
excluded from both coverage and formatting.

---

## Bloc lints

```sh
dart run bloc_tools:bloc lint .
```

Also available in VS Code via the [official bloc extension][bloc_extension_link]. See
<https://bloclibrary.dev/lint/>.

---

## App features

<!--
    TODO: describe the application's features here.
    This template currently ships only the counter sample from Very Good CLI.
-->

*Nothing yet — this template ships only the counter sample. Replace this section when real features
land.*

---

## License and attribution

MIT. See [LICENSE](LICENSE).

Generated by [Very Good CLI][very_good_cli_link].

The Flutter CI workflow consumed from `shared_workflow` is derived from
[VeryGoodOpenSource/very_good_workflows][very_good_workflows_link] at commit
`f053008378cc15a643a9050e67b0417bc548e7e8`, licensed under the MIT License,
Copyright (c) 2021 Very Good Ventures.

[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_cli_link]: https://github.com/VeryGoodOpenSource/very_good_cli
[very_good_workflows_link]: https://github.com/VeryGoodOpenSource/very_good_workflows
[shared_scripts_link]: https://github.com/ekawijayasusilo/shared_scripts
[internationalization_link]: https://docs.flutter.dev/ui/internationalization
[arb_documentation_link]: https://github.com/google/app-resource-bundle
[bloc_extension_link]: https://marketplace.visualstudio.com/items?itemName=FelixAngelov.bloc
