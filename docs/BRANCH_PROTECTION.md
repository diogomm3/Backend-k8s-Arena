# Branch Protection Settings for `main`

Apply these settings via GitHub UI: **Settings → Branches → Branch protection rules → Add rule**

## Required Settings

| Setting | Value |
|---------|-------|
| Branch name pattern | `main` |
| Require a pull request before merging | ✅ Enabled |
| Require approvals | 1 (minimum) |
| Dismiss stale PR approvals when new commits are pushed | ✅ Enabled |
| Require review from Code Owners | ❌ Disabled (no CODEOWNERS file yet) |
| Require status checks to pass before merging | ✅ Enabled |
| Require branches to be up to date before merging | ✅ Enabled |
| Status checks required (after this PR runs once) | `markdownlint`, `shellcheck`, `yamllint`, `DB Seed & Check` |
| Require conversation resolution before merging | ✅ Enabled |
| Require signed commits | ❌ Disabled (optional, can enable later) |
| Require linear history | ✅ Enabled |
| Do not allow bypassing the above settings | ✅ Enabled |
| Restrict who can push to matching branches | ✅ Enabled (admins only) |
| Allow force pushes | ❌ Disabled |
| Allow deletions | ❌ Disabled |
| **Automatically delete head branches** | ❌ **Disabled** (per AGENT.md rule) |

## Notes

- After this PR runs once, the check names (`markdownlint`, `shellcheck`, `yamllint`, `DB Seed & Check`) will appear in the status checks list. Enable all four as required checks.
- The `ci-template` workflow is reusable and not directly triggered on PRs; it will be called by backend-specific workflows later (T10+).
- The `ci-db.yml` workflow applies schema, runs the small seed (1k users, 10k posts, 40k likes), and runs `db-check` to verify row counts, checksums, and canonical query behavior.
- Never delete branches, local or remote, before or after a merge (per AGENT.md).
