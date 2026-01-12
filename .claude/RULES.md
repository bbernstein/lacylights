# Shared Development Rules

Rules that apply to all LacyLights repositories.

## Code Quality Standards

### All Languages
- All code must be linted before committing
- All code must have passing unit tests
- Coverage must meet or exceed repository thresholds
- Never lower coverage thresholds without explicit approval

### TypeScript (lacylights-fe, lacylights-mcp)
- Format with Prettier
- Lint with ESLint
- Test with Jest
- Document with JSDoc

### Go (lacylights-go, lacylights-test)
- Lint with golangci-lint
- Test with go test
- Use table-driven tests

### Swift (lacylights-mac)
- Format with SwiftFormat
- Lint with SwiftLint
- Documentation comments required

### Terraform (lacylights-terraform)
- Format with terraform fmt
- Validate with terraform validate
- Never commit state files or credentials

## Source Control

### Branch Management
- Never commit directly to `main` branch
- Create feature branches for all changes
- Use descriptive branch names: `feature/`, `fix/`, `docs/`
- If already on a non-main branch, use that branch

### Commit Messages
- Write clear, descriptive commit messages
- Focus on "why" rather than "what"
- Include all relevant context

### Pull Requests
- All changes must go through PR review
- Address all review comments before merging
- Wait for CI checks to pass
- Never merge without approval

## PR Iteration Workflow

When asked to "iterate on a PR":
1. Review and address any PR comments
2. After addressing comments, request new reviews
3. List which conversations should be marked resolved
4. Wait for new automated reviews
5. Address any new feedback
6. Wait for running checks to complete
7. Address any failing checks
8. If tests fail, determine if code or test is incorrect
9. If lint fails, fix lint errors
10. If coverage fails, add tests
11. If merge conflicts, resolve them
12. Never merge automatically - always request user approval
13. Add a summary comment after each round of changes

## Security

- Never commit credentials, API keys, or secrets
- Never commit production passwords
- Never commit personal information (names, phones, addresses)
- Add sensitive files to `.gitignore`
- Warn user if they request committing sensitive files

## Pre-Commit Checklist

Before committing any code:
1. Run linter - all warnings are errors
2. Run formatter for the language
3. Run all tests - must pass
4. Check coverage thresholds
5. Verify on correct branch (not main)
