# Claude Release Automation

Automated release script designed for AI coding assistants (especially Claude Code) to handle the complete release process non-interactively.

## Features

- **Automatic version detection** from git tags
- **Smart release note generation** from commit messages
- **GitHub release creation** via gh CLI
- **Homebrew tap updates** (if present)
- **Complete verification** of release process
- **Non-interactive** - perfect for AI automation

## Prerequisites

- `git` - Version control
- `gh` - GitHub CLI for release creation
- A GitHub repository with origin remote
- Optional: `~/homebrew-tap` directory for formula updates

## Usage

```bash
# Patch release (auto-generated notes)
./release.sh patch

# Minor release
./release.sh minor

# Major release
./release.sh major

# Specific version
./release.sh v1.2.3

# Custom release notes
./release.sh patch "Custom release message"
```

## How It Works

1. **Analyzes recent commits** for changelog generation
2. **Increments version** based on current git tags
3. **Categorizes commits** into features, fixes, improvements
4. **Creates git tag** and pushes to origin
5. **Generates GitHub release** with formatted notes
6. **Updates Homebrew formula** (if `~/homebrew-tap` exists)
7. **Verifies** all steps completed successfully

## Installation

```bash
# Make executable
chmod +x release.sh

# Optional: Install globally
sudo cp release.sh /usr/local/bin/release
```

## Claude Code Integration

This script is designed for Claude Code to automate releases. Simply drop it in any project and run:

```bash
./release.sh patch
```

The script automatically detects the repository context and handles everything else.

## Recent Fixes

- **v1.0.1**: Fixed sed regex for Homebrew formula version updates (ensures URLs properly update from v1.0.2 → v1.0.4)

## License

MIT - Use freely in any project!