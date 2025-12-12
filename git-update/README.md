# Git Repository Manager

A bash script to interactively manage Git repositories across GitHub and GitLab with clone, fetch, and push operations—individually or in batch.

## Overview

This script provides a persistent menu-driven interface to manage multiple Git repositories. It supports:

- Cloning from GitHub or GitLab (single or all)
- Fetching updates from either platform (single or all)
- Pushing to one or both platforms (single or all)
- Continuous operation via menu loop

## Prerequisites

- Git installed and configured
- SSH keys or HTTPS credentials set up for GitHub and/or GitLab
- Bash shell environment

## Configuration

Edit the script to add your repositories to the appropriate arrays:

```bash
# GitHub repositories
github_repos=(
    "https://github.com/username/repo1.git"
    "https://github.com/username/repo2.git"
)

# GitLab repositories
gitlab_repos=(
    "https://gitlab.com/username/repo1.git"
    "https://gitlab.com/username/repo2.git"
)

# Default branch (change to 'master' if needed)
DEFAULT_BRANCH="main"
```

**Note:** For "Push to Both" operations, ensure matching repositories are at the same index in both arrays.

## Usage

```bash
chmod +x git-manager.sh
./git-manager.sh
```

The script runs in a continuous loop until you select Quit.

## Menu Options

```
  Single Repository:
    1) Clone a repository
    2) Fetch from a repository
    3) Push to a repository

  Batch Operations:
    4) Clone ALL repositories
    5) Fetch ALL repositories
    6) Push ALL repositories

    q) Quit
```

### Single Repository Operations

**1) Clone** - Select platform → Select repo → Clone to current directory

**2) Fetch** - Select platform → Select repo → Fetch all branches with optional pull

**3) Push** - Choose destination:
  - GitHub only
  - GitLab only
  - Both (configures dual remotes)

### Batch Operations

**4) Clone ALL** - Clone all repos from:
  - All GitHub repos
  - All GitLab repos
  - All repos (both platforms)

**5) Fetch ALL** - Fetch and pull all repos from:
  - All GitHub repos
  - All GitLab repos
  - All repos (both platforms)

**6) Push ALL** - Push all repos to:
  - All GitHub repos
  - All GitLab repos
  - All repos to both platforms (dual remote)

Batch push prompts for a single commit message applied to all repos.

## Example Session

```
╔═══════════════════════════════════════╗
║       Git Repository Manager          ║
╚═══════════════════════════════════════╝

Current directory: /home/user/projects

What would you like to do?
─────────────────────────────────────────

  Single Repository:
    1) Clone a repository
    2) Fetch from a repository
    3) Push to a repository

  Batch Operations:
    4) Clone ALL repositories
    5) Fetch ALL repositories
    6) Push ALL repositories

    q) Quit

Select operation: 5

Select which repositories to fetch:
  1) All GitHub repos
  2) All GitLab repos
  3) All repos (both platforms)

Select option (1-3): 3

═══════════════════════════════════════
  Fetching all repositories
═══════════════════════════════════════

── GitHub ──

📥 Fetching updates for repo1...
   Pulling from main...
✅ Fetch complete for repo1

📥 Fetching updates for repo2...
   Pulling from main...
✅ Fetch complete for repo2

── GitLab ──

📥 Fetching updates for repo1...
   Pulling from main...
✅ Fetch complete for repo1

─────────────────────────────────────────
Press Enter to continue...
```

## How It Works

1. **Menu Loop**: Script continuously presents options until user quits
2. **Single Operations**: Interactive prompts for each step
3. **Batch Operations**: Auto-mode skips confirmations, applies single commit message
4. **Dual Remote Push**: Configures separate `github` and `gitlab` remotes on local repo

## Batch Mode Behavior

When running batch operations:
- **Clone**: Skips existing directories instead of prompting
- **Fetch**: Automatically pulls from default branch
- **Push**: Stages all changes, uses provided commit message (or dated default)

## Notes

- Default branch is `main` (configurable via `DEFAULT_BRANCH`)
- Empty commit messages default to "Update YYYY-MM-DD"
- Screen clears between menu displays for cleaner output
- Batch operations show progress for each repository

## Limitations

- "Push to Both" assumes repo names match at the same array index
- No merge conflict handling
- No branch selection (uses default branch only)
- Batch clone skips (doesn't re-clone) existing directories

## Changelog

- **v1.1** - Added batch operations (clone/fetch/push all), menu loop
- **v1.0** - Initial release with single repo operations