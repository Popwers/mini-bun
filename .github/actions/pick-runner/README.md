# pick-runner

Composite action that picks where CI jobs run. Jobs use a GitHub-hosted runner while the owner has enough included Actions minutes left. They move to the self-hosted build server when the quota runs low. Bash, `curl` and `jq` only, all preinstalled on GitHub-hosted runners.

## Usage

```yaml
jobs:
  pick-runner:
    # Owner with a self-hosted build server: run this job there (see below).
    runs-on: ${{ fromJSON(vars.CI_PICK_RUNNER_ON || '["self-hosted","ARM64"]') }}
    # Owner without a self-hosted runner: runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    outputs:
      runner: ${{ steps.pick.outputs.runner }}
      target: ${{ steps.pick.outputs.target }}
    steps:
      - id: pick
        uses: Popwers/mini-bun/.github/actions/pick-runner@<sha>
        with:
          force: ${{ inputs.runner != '' && inputs.runner != 'auto' && inputs.runner || vars.CI_FORCE_RUNNER }}
          threshold: ${{ vars.CI_QUOTA_THRESHOLD || '10' }}
          token: ${{ secrets.CI_BILLING_TOKEN }}

  build:
    needs: pick-runner
    runs-on: ${{ fromJSON(needs.pick-runner.outputs.runner) }}
```

## Where the pick-runner job runs

GitHub never moves a queued job to another runner. If `pick-runner` itself sits on `ubuntu-latest` and the Actions quota is spent (private repository, spending limit reached), GitHub never starts it, and every job that `needs` it waits forever. So:

- **Owner with a build server** (mystudio-digital): `runs-on: ${{ fromJSON(vars.CI_PICK_RUNNER_ON || '["self-hosted","ARM64"]') }}`. The job takes a few seconds on the build server and spends no GitHub minute. While the quota lasts it still outputs `"ubuntu-latest"`, so the following jobs keep running on GitHub. Once the quota is spent the following jobs go to the build server, and the CI passes anyway.
- Escape hatch when the build server is down or stuck: set the repository or organization variable `CI_PICK_RUNNER_ON` to `"ubuntu-latest"` (JSON, quotes included) and also `CI_FORCE_RUNNER=github`. This brings back the old behaviour.
- **Owner without a self-hosted runner** (Popwers repositories): keep `runs-on: ubuntu-latest`. A self-hosted label there would queue forever. Public repositories (mini-bun, astrojs-template, strapi-template) do not use the quota, so they are not affected. A private one (tete-anler) still stops when the account quota is spent: it has no runner to fall back to.

Limits: on a build server with one busy runner, `pick-runner` waits for a free slot before the GitHub jobs can start. If the build server is offline, CI waits until the escape hatch is set. The first step of the action, `Show runner`, prints where the job ran. Without `jq` on the runner the quota is not read and the build server is picked (unless `force: github`).

## Inputs

| Input | Default | Role |
| --- | --- | --- |
| `token` | empty | Token that reads billing usage. Empty means the build server. |
| `force` | empty | `github` or `build-server` skips the quota check. Case-insensitive. Any other value means auto. |
| `threshold` | `10` | Remaining percentage under which jobs go to the build server. |
| `github-runner` | `ubuntu-latest` | GitHub-hosted label. A repo that needs ARM passes `ubuntu-24.04-arm`. |
| `build-server-runner` | `["self-hosted","ARM64"]` | JSON array of self-hosted labels. |
| `included-minutes` | empty | Included monthly minutes. Overrides the plan lookup. |

## Outputs

| Output | Example | Role |
| --- | --- | --- |
| `runner` | `"ubuntu-latest"` or `["self-hosted","ARM64"]` | JSON for `runs-on: ${{ fromJSON(...) }}`. |
| `target` | `github` | `github` or `build-server`. |
| `remaining-percent` | `92.5` | Empty when the quota was not read. |
| `reason` | `92.5% of 3000 minutes left (plan team)` | Also written to the step summary. |

## Decision

1. `force` wins.
2. A public repository uses GitHub-hosted runners, which are free there.
3. No token means the build server, with a warning.
4. Used minutes are the sum of `grossQuantity` over the `minutes` items of the billing usage summary for the current month. Included minutes come from `included-minutes` or the plan: free 2000, pro and team 3000, enterprise 50000, anything else 2000.
5. Below `threshold` percent remaining, jobs go to the build server.

Any API, JSON or parsing failure picks the build server with a warning. The step never fails the job.

## CI_BILLING_TOKEN

Create a fine-grained personal access token.

- Organization owner. Set the resource owner to the organization and grant the organization permission **Administration: Read-only**. The token creator must be an owner or billing manager of the organization.
- User owner. Create the token on the account and grant the account permission **Plan: Read-only**.

Store it as the `CI_BILLING_TOKEN` secret of the repository or organization.

## Local test

```sh
./tests/pick-runner.test.sh
```

The test serves API fixtures from a local `python3` server and points the script at it through `PICK_RUNNER_API_URL` (default `https://api.github.com`). The script reads its inputs from `PICK_*` variables, so it also runs by hand:

```sh
PICK_FORCE=github bash .github/actions/pick-runner/pick-runner.sh
```
