# KVC Git Commit Standard

Version 1.0 — 2026-03-08

This document defines the commit message standard for all Kyvero Vexus
repositories. Every contributor (human or agent) MUST follow it.

## Format

```
type(scope): Subject in imperative mood

Body explaining why this change exists, what was wrong before,
what this enables, and any non-obvious consequences.

Further paragraphs separated by blank lines if needed.

Footer(s)
```

## Subject Line

- **Structure:** `type(scope): Summary`
- **Length:** aim for ~50 chars, hard limit 72 chars
- **Mood:** imperative ("Add", "Fix", "Refactor" — not "Added", "Fixes")
- **Capitalization:** capitalize the first word after the colon
- **Punctuation:** no trailing period
- **Content:** one commit = one logical change = one type

The subject line MUST complete this sentence naturally:

> If applied, this commit will **\<your subject here\>**

## Types

| Type       | When to use                                        |
|------------|----------------------------------------------------|
| `feat`     | New feature or capability                          |
| `fix`      | Bug fix                                            |
| `refactor` | Code restructuring with no behavior change         |
| `perf`     | Performance improvement                            |
| `docs`     | Documentation only                                 |
| `test`     | Adding or updating tests                           |
| `ci`       | CI/CD pipeline changes                             |
| `build`    | Build system, dependencies, packaging              |
| `chore`    | Routine maintenance (formatting, renaming, config) |
| `revert`   | Reverting a previous commit                        |

If a commit genuinely spans two types, split it into two commits.

## Scope

Scope is **optional but encouraged** when the repo has multiple
components or subsystems. It is a short noun in parentheses naming the
area of the codebase affected.

Examples:
- `feat(cl-llm): Add Codex OAuth provider`
- `fix(telegram): Handle empty message bodies`
- `docs(README): Update installation instructions`
- `refactor(memory): Simplify compaction logic`

When the change is truly global or cross-cutting, omit the scope:
- `chore: Update .gitignore for build artifacts`

Each repository SHOULD maintain a list of recognized scopes in its
own CONTRIBUTING.md or README. Scopes are lowercase, hyphenated if
multi-word.

## Body

The body is **REQUIRED** for all commits except:
- Typo fixes (`docs: Fix typo in README`)
- Version bumps (`build: Bump SBCL to 2.5.3`)
- Trivially self-evident one-liners

The body explains **why**, not how. The diff shows how. Answer these
questions:

1. **What was the problem or motivation?**
2. **What does this change enable?**
3. **Are there non-obvious side effects or consequences?**
4. **Were alternatives considered? Why this approach?** (when relevant)

Rules:
- Separate from subject with a blank line
- Wrap at 72 characters
- Use paragraphs, bullet points, or numbered lists as appropriate
- Write in present tense ("This enables..." not "This enabled...")

## Footers

Footers use [git trailer format](https://git-scm.com/docs/git-interpret-trailers)
and appear after the body, separated by a blank line.

| Footer              | Purpose                                     |
|---------------------|---------------------------------------------|
| `Closes: bd-42`     | Closes a beads issue on merge               |
| `Fixes: bd-17`      | Fixes a beads issue (alias for Closes)      |
| `Refs: bd-99`       | References an issue without closing it       |
| `BREAKING CHANGE:`  | Describes a breaking API/behavior change     |
| `Co-authored-by:`   | Credit co-authors (full `Name <email>` form) |
| `Reviewed-by:`      | Credit reviewer (name or agent id)           |
| `Tested-by:`        | Credit tester                                |

Multiple footers are fine. One per line.

### Breaking Changes

A breaking change MUST be indicated by either:
- A `!` after the type/scope: `feat(api)!: Remove legacy endpoint`
- A `BREAKING CHANGE:` footer with a description

When using `!`, a `BREAKING CHANGE:` footer is still RECOMMENDED to
explain the impact.

## Examples

### Minimal (trivial change, no body needed)

```
docs: Fix typo in cl-llm README
```

### Standard (most commits should look like this)

```
fix(telegram): Handle empty message bodies gracefully

The Telegram provider crashes with a nil dereference when receiving
a message with no text content (e.g., sticker-only messages). This
happens because parse-message assumes body is always a string.

Add a nil guard in parse-message and return an empty-body message
object instead of crashing. This also unblocks downstream handlers
that need to process media-only messages.

Closes: bd-42
```

### Feature with breaking change

```
feat(cl-llm)!: Replace provider keyword args with config objects

Provider initialization previously used a flat keyword argument
list, which became unwieldy as providers gained more options
(timeouts, retry policies, auth modes). Config objects group
related settings, enable validation at construction time, and
make provider defaults explicit.

Existing code using (make-provider :openai :api-key "...") must
migrate to (make-provider :openai (make-config :api-key "...")).
A migration guide is in docs/MIGRATION-v2.md.

BREAKING CHANGE: All make-provider calls must use config objects
instead of flat keyword arguments.
Closes: bd-88
Refs: bd-71
```

### Revert

```
revert: Remove experimental caching in memory search

This reverts commit a1b2c3d.

The LRU cache introduced in a1b2c3d causes stale results when
memory files are updated between searches. Reverting until we
implement proper cache invalidation.

Refs: bd-103
```

### Multi-paragraph body

```
refactor(core): Extract session lifecycle into dedicated module

Session creation, persistence, and cleanup were spread across
three files (main.lisp, server.lisp, persistence.lisp) with
duplicated state management. This made it difficult to reason
about session invariants and introduced subtle bugs when one
path updated state differently from another.

The new session-lifecycle module centralizes all session state
transitions behind a single API. Other modules now go through
with-session and ensure-session instead of manipulating session
slots directly.

This does not change any external behavior or wire protocol.
Tests updated to use the new API.

Closes: bd-55
```

## Atomic Commits

Each commit MUST be a single logical change. If you find yourself
writing "and" in the subject line, you probably need two commits.

Good:
- `fix(parser): Handle escaped quotes in string literals`
- `test(parser): Add escaped-quote edge cases`

Bad:
- `fix(parser): Handle escaped quotes and add tests and update docs`

Benefits of atomic commits:
- `git bisect` works reliably
- `git revert` targets exactly one change
- `git log --oneline` tells a coherent story
- Code review is focused and fast

## Commit Signing

All commits MUST be GPG-signed. This is already configured globally
via `commit.gpgsign=true`. If you see unsigned commits, check your
GPG agent.

## Git Commit Template

A `.gitmessage` template is provided in the repository root. It is
configured automatically via:

```bash
git config commit.template .gitmessage
```

The template provides the structure as a reminder. Delete the
comment lines before committing.

## Enforcement

For now, this standard is enforced by convention and code review.
Future tooling may include:
- A pre-commit hook validating subject format
- CI checks via commitlint or equivalent
- Automated changelog generation from commit history

## References

- [How to Write a Git Commit Message](https://cbea.ms/git-commit/)
  — Chris Beams' seven rules
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
  — The structured-header spec we build on
- [Linux Kernel Submitting Patches](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)
  — Gold standard for body quality and trailer discipline
- [Angular Commit Guidelines](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md)
  — Origin of the type(scope) pattern
