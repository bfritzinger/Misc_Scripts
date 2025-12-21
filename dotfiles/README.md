# Dotfiles

Personal configuration files for setting up a new Linux system.

## Quick Start

### One-liner install (after pushing to GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/dotfiles/main/bootstrap.sh | bash
```

### Manual install

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x bootstrap.sh
./bootstrap.sh
```

## What's Included

| File | Description |
|------|-------------|
| `bootstrap.sh` | Main installation script - installs packages and links configs |
| `.bashrc` | Bash configuration with prompt, functions, and completions |
| `.bash_aliases` | Comprehensive aliases for common commands |
| `.vimrc` | Vim configuration with plugins (vim-plug) |
| `.tmux.conf` | Tmux configuration with better key bindings |
| `.gitconfig` | Git configuration with aliases and defaults |
| `.gitignore_global` | Global gitignore patterns |

## Customization

### Local Overrides

Create these files for machine-specific settings (not tracked in git):

- `~/.bashrc.local` - Local bash settings
- `~/.bashrc.work` - Work-specific settings
- `~/.gitconfig.local` - Local git settings (include in main .gitconfig)

### Before Using

1. Update `.gitconfig` with your name and email
2. Modify `bootstrap.sh` to add/remove packages as needed
3. Adjust timezone in `configure_system()` if needed

## Key Features

### Bash
- Git branch in prompt
- Useful functions: `mkcd`, `extract`, `backup`, `psgrep`, `serve`
- History configuration with timestamps
- Tab completion for kubectl, helm, docker

### Aliases (highlights)

```bash
# Kubernetes
k        # kubectl
kgp      # kubectl get pods
kgpa     # kubectl get pods -A
kl       # kubectl logs
kex      # kubectl exec -it

# Docker
d        # docker
dc       # docker compose
dps      # docker ps
dcu      # docker compose up -d

# Git
gs       # git status
gp       # git push
gpl      # git pull
gcm      # git commit -m
glog     # pretty git log

# System
ll       # ls -alFh
update   # apt update && upgrade
```

### Vim
- Space as leader key
- NERDTree (`<leader>n`)
- FZF fuzzy finder (`<leader>ff`, `<leader>fs`)
- Git integration (fugitive, gitgutter)
- Sensible defaults (line numbers, syntax highlighting, etc.)

### Tmux
- `Ctrl-a` as prefix (instead of Ctrl-b)
- Mouse support enabled
- Vi-style copy mode
- `|` and `-` for splits
- Session persistence with tmux-resurrect

## Architecture Support

The bootstrap script detects and handles:
- x86_64 (amd64)
- aarch64 (arm64) - Raspberry Pi, Jetson
- armv7l (armhf)

## Manual Steps After Install

1. **SSH Key**: Run `ssh-keygen` if you skipped during install
2. **Git Config**: Update name/email in `~/.gitconfig`
3. **Vim Plugins**: Run `:PlugInstall` in vim
4. **Tmux Plugins**: Press `prefix + I` to install TPM plugins
5. **Logout/Login**: Required for docker group membership

## Directory Structure

```
~/dotfiles/
├── bootstrap.sh          # Main installer
├── README.md
├── .bashrc
├── .bash_aliases
├── .bash_profile
├── .vimrc
├── .tmux.conf
├── .gitconfig
├── .gitignore_global
├── .ssh/
│   └── config           # SSH host configurations
└── .config/
    └── ...              # Application configs
```

## Updating

```bash
cd ~/dotfiles
git pull
./bootstrap.sh  # Re-run to update symlinks
```

## Uninstalling

The original files are backed up to `~/.dotfiles_backup_TIMESTAMP/`. To restore:

```bash
# Find your backup
ls -la ~/.dotfiles_backup_*

# Restore files
cp ~/.dotfiles_backup_YYYYMMDD_HHMMSS/.bashrc ~/
# ... repeat for other files
```

## Adding New Machines

1. Clone this repo
2. Run bootstrap.sh
3. Create `~/.bashrc.local` for machine-specific settings
4. Done!

## License

MIT - Do whatever you want with it.
