---
name: commit
description: Stage changes, generate a conventional commit message, and commit.
argument-hint: "[optional: override commit message]"
disable-model-invocation: true
allowed-tools: Read, Bash
---

## Current Changes

!`git status --short`

## Diff Summary

!`git diff --stat`

## Detailed Changes

!`git diff`

Based on the changes above:

1. Stage all modified/added files (excluding .env, secrets, build artifacts)
2. **Check if staged files touch a security-sensitive path** (webhook/callback
   route, auth/session code, `Dockerfile`, payment/banking integration,
   migrations). If so, invoke the `security-check` skill on those files
   *before* committing — `pre-commit-security-gate.sh` blocks the commit
   otherwise. Add a trailer to the commit message reflecting the result:
   `Security-check: ok (sem findings críticos)` or
   `Security-check: findings corrigidos (resumo curto)`.
3. Generate a conventional commit message: `type(scope): description`
   - `feat` for new features
   - `fix` for bug fixes
   - `refactor` for code restructuring
   - `docs` for documentation
   - `test` for test additions/changes
   - `chore` for maintenance tasks
   - `ci` for CI/CD changes
4. If the user provided a message via $ARGUMENTS, use that instead
5. Show the commit message and ask for confirmation before committing
6. Do NOT push — let the user decide when to push
