# Contributing to nExBot

Thanks for your interest in contributing! This guide explains how to get started and the contribution guidelines.

## Code of Conduct
Be respectful, follow community standards, and open issues or PRs politely.

## Getting started (developer)
1. Fork the repo
2. Clone: `git clone <your-fork>`
3. Use a recent OTClientV8 build and copy the `nExBot` folder to `%APPDATA%/OTClientV8/<your-config>/bot/`

## Running locally
- Edit Lua files in `core/` and `cavebot/` and reload the bot in-client.
- Use debug logs and inspect EventBus events.

## Tests & Checks

Run the full quality gate before submitting:

```bash
make check    # lint + test
make test     # busted tests/
make lint     # luacheck .
```

Test framework: **Busted** (Lua BDD). Tests live in `tests/`.

```bash
# Run all tests
busted tests/

# Run specific module tests
busted tests/unit/containers/

# Run with verbose output
busted tests/ -v
```

## PR guidelines
- Small, focused PRs are preferred
- Include a short description, motivation, and test steps
- Run `make check` before submitting
- Update `CHANGELOG.md` for notable changes

## Style
- Follow the existing Lua style (2-space indentation)
- Use descriptive function and variable names
- Keep functions small and focused
- Write tests for new features

## Issues
- Prefer opening an issue before a major change
- Label issues as `bug`/`enhancement`/`docs`

Thanks — maintainers will review your PRs as soon as possible.
