# Contributing to Offset

Thanks for helping improve Offset.

## Before You Start

- Use GitHub issues for bug reports, ideas, and feature discussions
- For larger changes, open an issue before starting implementation
- Keep pull requests scoped to one change when possible

## Development Setup

1. Install Xcode 17 or newer
2. Clone the repository
3. Open `Offset.xcodeproj` in Xcode, or use `./script/build_and_run.sh`
4. Run the test suite before submitting changes

## Code Style

- Follow the existing Swift style in the project
- Prefer small, focused changes over broad refactors
- Add tests when changing parsing logic, persistence behavior, or service presentation behavior
- Keep comments brief and only where they add clarity

## Pull Requests

Before opening a pull request:

- confirm the app builds locally
- run the test suite
- describe the user-facing impact
- note any follow-up work or limitations

## Reporting Bugs

Please include:

- the macOS version
- the Offset version or commit
- steps to reproduce
- expected behavior
- actual behavior

## Security

Please avoid posting sensitive personal data, tokens, or private screenshots in public issues.
