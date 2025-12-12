# Git Repository Manager

A bash script to interactively manage Git repositories across GitHub and GitLab with clone, fetch, and push operations—individually or in batch.

## Overview

This script provides a persistent menu-driven interface to manage multiple Git repositories. It supports:

- Cloning from GitHub or GitLab (single or all)
- Fetching updates from either platform (single or all)
- Pushing to one or both platforms (single or all)
- **Automatic sync before push** (prevents non-fast-forward rejections)
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

## Sync Before Push

The script automatically syncs with the remote before pushing to prevent "non-fast-forward" rejections. This handles the common scenario where your local branch is behind the remote.

**What it does:**

1. Fetches the latest from the remote
2. Compares local and remote HEAD
3. If local is behind → pulls with rebase
4. If branches diverged → attempts rebase, aborts on conflict
5. Then pushes

**If push still fails (single repo mode):**

```
❌ Push failed for repo-name

Options:
  1) Force push (overwrites remote - DANGEROUS)
  2) Skip this repo
```

**Conflict handling:**

If a rebase conflict is detected, the script automatically aborts the rebase and reports the failure. You'll need to manually resolve:

```bash
cd repo-name
git pull --rebase origin main
# Resolve conflicts
git rebase --continue
git push origin main
```

## Example Session

```
╔═══════════════════════════════════════╗
║       Git Repository Manager          ║
╚═══════════════════════════════════════╝

Current directory: /home/user/projects

Select operation: 3

Push to which remote?
  1) GitHub only
  2) GitLab only
  3) Both (same repo, dual remotes)

Select option (1-3): 1

Available GitHub repositories:
─────────────────────────────────
  1) repo1
  2) repo2

Select repository (1-2): 1

📊 Current status for repo1:
─────────────────────────────────
 M README.md

Stage all changes? (y/n): y
Enter commit message: Updated documentation

🔄 Syncing with remote before push...
   Local is behind remote, pulling...
Successfully rebased and updated refs/heads/main.

📤 Pushing to origin...
✅ Successfully pushed to repo1
```

## How It Works

1. **Menu Loop**: Script continuously presents options until user quits
2. **Single Operations**: Interactive prompts for each step
3. **Batch Operations**: Auto-mode skips confirmations, applies single commit message
4. **Sync Before Push**: Fetches and rebases before every push attempt
5. **Dual Remote Push**: Configures separate `github` and `gitlab` remotes on local repo

## Batch Mode Behavior

When running batch operations:
- **Clone**: Skips existing directories instead of prompting
- **Fetch**: Automatically pulls (with rebase) from default branch
- **Push**: Stages all changes, syncs with remote, uses provided commit message

## Notes

- Default branch is `main` (configurable via `DEFAULT_BRANCH`)
- Empty commit messages default to "Update YYYY-MM-DD"
- Screen clears between menu displays for cleaner output
- Uses `--rebase` for cleaner history (no merge commits)
- Force push option only available in single-repo interactive mode

## Limitations

- "Push to Both" assumes repo names match at the same array index
- Rebase conflicts require manual resolution
- No branch selection (uses default branch only)
- Batch clone skips (doesn't re-clone) existing directories
- Force push not available in batch mode (safety)

## Changelog

- **v1.2** - Added sync-before-push with auto-rebase, force push option on failure
- **v1.1** - Added batch operations (clone/fetch/push all), menu loop
- **v1.0** - Initial release with single repo operations