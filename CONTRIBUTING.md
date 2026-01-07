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
- There is no formal test-suite yet. Manual QA is required:
  - Start a client, enable the bot, replicate common flows (login, open containers, start cavebot) and monitor logs.

## PR guidelines
- Small, focused PRs are preferred
- Include a short description, motivation, and test steps
- Update `CHANGELOG.md` for notable changes

## Style
- Follow the existing Lua style (2-space indentation)
- Use descriptive function and variable names

## Issues
- Prefer opening an issue before a major change
- Label issues as `bug`/`enhancement`/`docs`

Thanks — maintainers will review your PRs as soon as possible.