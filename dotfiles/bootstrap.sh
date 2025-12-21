#!/bin/bash
#===============================================================================
# Bootstrap Script for Linux Environment Setup
# Author: Brian Fritzinger
# 
# Usage: 
#   curl -fsSL https://raw.githubusercontent.com/yourusername/dotfiles/main/bootstrap.sh | bash
#   -- or --
#   git clone https://github.com/yourusername/dotfiles.git ~/dotfiles && ~/dotfiles/bootstrap.sh
#===============================================================================

set -e  # Exit on error

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yourusername/dotfiles.git}"
LOG_FILE="/tmp/bootstrap_$(date +%Y%m%d_%H%M%S).log"

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------
info()    { echo -e "\033[1;34m[INFO]\033[0m $1" | tee -a "$LOG_FILE"; }
success() { echo -e "\033[1;32m[OK]\033[0m $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $1" | tee -a "$LOG_FILE"; exit 1; }

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        armv7l)  ARCH_TYPE="armhf" ;;
        *)       ARCH_TYPE="unknown" ;;
    esac
    info "Detected architecture: $ARCH ($ARCH_TYPE)"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    else
        OS_ID="unknown"
    fi
    info "Detected OS: $OS_NAME"
}

command_exists() {
    command -v "$1" &> /dev/null
}

#-------------------------------------------------------------------------------
# Package Installation
#-------------------------------------------------------------------------------
install_base_packages() {
    info "Installing base packages..."
    
    local packages=(
        # Core utilities
        git
        curl
        wget
        vim
        nano
        htop
        tmux
        tree
        unzip
        zip
        jq
        yq
        
        # Networking
        net-tools
        dnsutils
        iputils-ping
        traceroute
        nmap
        
        # Development
        build-essential
        python3
        python3-pip
        python3-venv
        
        # System monitoring
        sysstat
        iotop
        ncdu
        
        # Security
        ufw
        fail2ban
    )
    
    case "$OS_ID" in
        ubuntu|debian|raspbian)
            sudo apt update
            sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            sudo dnf install -y "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        arch|manjaro)
            sudo pacman -Syu --noconfirm "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            warn "Unknown package manager for $OS_ID - skipping base packages"
            ;;
    esac
    
    success "Base packages installed"
}

install_docker() {
    if command_exists docker; then
        info "Docker already installed: $(docker --version)"
        return
    fi
    
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    sudo systemctl enable docker
    sudo systemctl start docker
    success "Docker installed"
}

install_kubectl() {
    if command_exists kubectl; then
        info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
        return
    fi
    
    info "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_TYPE}/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    success "kubectl installed"
}

install_k9s() {
    if command_exists k9s; then
        info "k9s already installed"
        return
    fi
    
    info "Installing k9s..."
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    
    case "$ARCH_TYPE" in
        amd64) K9S_ARCH="amd64" ;;
        arm64) K9S_ARCH="arm64" ;;
        *)     warn "k9s not available for $ARCH_TYPE"; return ;;
    esac
    
    curl -sL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz" | sudo tar xz -C /usr/local/bin k9s
    success "k9s installed"
}

install_helm() {
    if command_exists helm; then
        info "Helm already installed: $(helm version --short)"
        return
    fi
    
    info "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    success "Helm installed"
}

#-------------------------------------------------------------------------------
# Dotfiles Setup
#-------------------------------------------------------------------------------
setup_dotfiles() {
    info "Setting up dotfiles..."
    
    # Clone repo if not present
    if [ ! -d "$DOTFILES_DIR" ]; then
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
    
    # Backup existing files
    local backup_dir="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # List of dotfiles to symlink
    local dotfiles=(
        ".bashrc"
        ".bash_aliases"
        ".bash_profile"
        ".vimrc"
        ".tmux.conf"
        ".gitconfig"
    )
    
    for file in "${dotfiles[@]}"; do
        if [ -f "$DOTFILES_DIR/$file" ]; then
            # Backup existing file if it exists and is not a symlink
            if [ -f "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
                mv "$HOME/$file" "$backup_dir/"
                info "Backed up existing $file"
            fi
            
            # Remove existing symlink if present
            [ -L "$HOME/$file" ] && rm "$HOME/$file"
            
            # Create symlink
            ln -sf "$DOTFILES_DIR/$file" "$HOME/$file"
            success "Linked $file"
        fi
    done
    
    # Handle .config directory items
    if [ -d "$DOTFILES_DIR/.config" ]; then
        mkdir -p "$HOME/.config"
        for dir in "$DOTFILES_DIR/.config"/*; do
            if [ -d "$dir" ]; then
                local dirname=$(basename "$dir")
                ln -sfn "$dir" "$HOME/.config/$dirname"
                success "Linked .config/$dirname"
            fi
        done
    fi
    
    success "Dotfiles setup complete"
}

#-------------------------------------------------------------------------------
# SSH Setup
#-------------------------------------------------------------------------------
setup_ssh() {
    info "Setting up SSH..."
    
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Generate SSH key if not present
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        read -p "Generate new SSH key? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter email for SSH key: " ssh_email
            ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519"
            success "SSH key generated"
            info "Public key:"
            cat "$HOME/.ssh/id_ed25519.pub"
        fi
    else
        info "SSH key already exists"
    fi
    
    # Copy SSH config if present in dotfiles
    if [ -f "$DOTFILES_DIR/.ssh/config" ]; then
        cp "$DOTFILES_DIR/.ssh/config" "$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
        success "SSH config installed"
    fi
}

#-------------------------------------------------------------------------------
# Python Environment
#-------------------------------------------------------------------------------
setup_python() {
    info "Setting up Python environment..."
    
    # Ensure pip is up to date
    python3 -m pip install --upgrade pip --break-system-packages 2>/dev/null || \
    python3 -m pip install --upgrade pip
    
    # Common Python packages
    local pip_packages=(
        pipx
        virtualenv
        ipython
        requests
        pyyaml
        python-dotenv
    )
    
    for pkg in "${pip_packages[@]}"; do
        python3 -m pip install "$pkg" --break-system-packages 2>/dev/null || \
        python3 -m pip install "$pkg" --user
    done
    
    # Ensure pipx path
    python3 -m pipx ensurepath 2>/dev/null || true
    
    success "Python environment configured"
}

#-------------------------------------------------------------------------------
# Vim Setup
#-------------------------------------------------------------------------------
setup_vim() {
    info "Setting up Vim..."
    
    # Install vim-plug
    if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        success "vim-plug installed"
    fi
    
    # Create undo directory
    mkdir -p "$HOME/.vim/undodir"
    
    success "Vim setup complete"
}

#-------------------------------------------------------------------------------
# System Configuration
#-------------------------------------------------------------------------------
configure_system() {
    info "Configuring system settings..."
    
    # Set timezone (modify as needed)
    # sudo timedatectl set-timezone America/New_York
    
    # Enable useful services
    sudo systemctl enable --now ssh 2>/dev/null || true
    
    # Configure UFW basics (if desired)
    # sudo ufw default deny incoming
    # sudo ufw default allow outgoing
    # sudo ufw allow ssh
    # sudo ufw --force enable
    
    success "System configuration complete"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    echo "=============================================="
    echo "  Linux Environment Bootstrap Script"
    echo "=============================================="
    echo ""
    
    detect_arch
    detect_os
    
    echo ""
    echo "This script will install and configure:"
    echo "  - Base development packages"
    echo "  - Docker"
    echo "  - Kubernetes tools (kubectl, k9s, helm)"
    echo "  - Dotfiles and shell configuration"
    echo "  - Python environment"
    echo "  - Vim configuration"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi
    
    echo ""
    
    # Run installation steps
    install_base_packages
    install_docker
    install_kubectl
    install_k9s
    install_helm
    setup_dotfiles
    setup_ssh
    setup_python
    setup_vim
    configure_system
    
    echo ""
    echo "=============================================="
    success "Bootstrap complete!"
    echo "=============================================="
    echo ""
    info "Log file: $LOG_FILE"
    info "Please log out and back in (or run 'newgrp docker') for group changes to take effect."
    info "Run 'source ~/.bashrc' to load new shell configuration."
    echo ""
}

# Run main function
main "$@"
