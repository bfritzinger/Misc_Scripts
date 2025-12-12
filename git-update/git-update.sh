#!/bin/bash

# =============================================================================
# Git Repository Manager
# Manage clone, push, and fetch operations across GitHub and GitLab repos
# =============================================================================

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

# =============================================================================
# Functions
# =============================================================================

# Display a numbered list and get selection
select_repo() {
    local -n repos=$1
    local platform=$2
    local i=1
    
    echo ""
    echo "Available $platform repositories:"
    echo "─────────────────────────────────"
    for repo in "${repos[@]}"; do
        repo_name=$(basename "$repo" .git)
        echo "  $i) $repo_name"
        ((i++))
    done
    echo ""
    
    read -p "Select repository (1-${#repos[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#repos[@]}" ]; then
        selected_repo="${repos[$((selection-1))]}"
        return 0
    else
        echo "Invalid selection."
        return 1
    fi
}

# Clone a repository
do_clone() {
    local repo_url=$1
    local auto_mode=${2:-false}
    local repo_name=$(basename "$repo_url" .git)
    
    if [ -d "$repo_name" ]; then
        echo "⚠️  Directory '$repo_name' already exists."
        if [ "$auto_mode" = true ]; then
            echo "   Skipping (auto mode)..."
            return 1
        fi
        read -p "Remove and re-clone? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$repo_name"
        else
            echo "Clone cancelled."
            return 1
        fi
    fi
    
    echo "📥 Cloning $repo_name..."
    git clone "$repo_url"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully cloned $repo_name"
    else
        echo "❌ Failed to clone $repo_name"
        return 1
    fi
}

# Fetch from a repository
do_fetch() {
    local repo_url=$1
    local auto_mode=${2:-false}
    local repo_name=$(basename "$repo_url" .git)
    
    if [ ! -d "$repo_name" ]; then
        echo "❌ Directory '$repo_name' does not exist. Clone it first."
        return 1
    fi
    
    echo "📥 Fetching updates for $repo_name..."
    cd "$repo_name"
    git fetch --all
    
    if [ "$auto_mode" = true ]; then
        echo "   Pulling from $DEFAULT_BRANCH..."
        git pull --rebase origin "$DEFAULT_BRANCH" 2>/dev/null || echo "   ⚠️  Pull failed or nothing to pull"
    else
        echo ""
        echo "Remote branches:"
        git branch -r
        echo ""
        read -p "Pull changes from $DEFAULT_BRANCH? (y/n): " pull_confirm
        if [[ "$pull_confirm" =~ ^[Yy]$ ]]; then
            git pull --rebase origin "$DEFAULT_BRANCH"
        fi
    fi
    cd ..
    
    echo "✅ Fetch complete for $repo_name"
}

# Sync with remote before push (pull --rebase)
sync_before_push() {
    local remote_name=${1:-origin}
    
    echo "🔄 Syncing with remote before push..."
    git fetch "$remote_name" "$DEFAULT_BRANCH" 2>/dev/null
    
    # Check if we're behind
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse "$remote_name/$DEFAULT_BRANCH" 2>/dev/null)
    BASE=$(git merge-base HEAD "$remote_name/$DEFAULT_BRANCH" 2>/dev/null)
    
    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "   Already up to date."
    elif [ "$LOCAL" = "$BASE" ]; then
        echo "   Local is behind remote, pulling..."
        git pull --rebase "$remote_name" "$DEFAULT_BRANCH"
    elif [ "$REMOTE" = "$BASE" ]; then
        echo "   Local is ahead, ready to push."
    else
        echo "   Branches have diverged, attempting rebase..."
        git pull --rebase "$remote_name" "$DEFAULT_BRANCH"
        if [ $? -ne 0 ]; then
            echo "   ⚠️  Rebase conflict detected!"
            echo "   Aborting rebase..."
            git rebase --abort 2>/dev/null
            return 1
        fi
    fi
    return 0
}

# Push to a repository
do_push() {
    local repo_url=$1
    local auto_mode=${2:-false}
    local commit_msg=${3:-""}
    local repo_name=$(basename "$repo_url" .git)
    
    if [ ! -d "$repo_name" ]; then
        echo "❌ Directory '$repo_name' does not exist."
        return 1
    fi
    
    cd "$repo_name"
    
    # Show status
    echo ""
    echo "📊 Current status for $repo_name:"
    echo "─────────────────────────────────"
    git status -s
    echo ""
    
    # Check if there are changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "No changes to commit."
        if [ "$auto_mode" = true ]; then
            echo "   Syncing and pushing any existing commits..."
            sync_before_push "origin"
            git push origin "$DEFAULT_BRANCH" 2>/dev/null
            cd ..
            return 0
        fi
        read -p "Push existing commits anyway? (y/n): " push_anyway
        if [[ ! "$push_anyway" =~ ^[Yy]$ ]]; then
            cd ..
            return 0
        fi
    else
        if [ "$auto_mode" = true ]; then
            git add -A
            if [ -z "$commit_msg" ]; then
                commit_msg="Update $(date +%Y-%m-%d)"
            fi
            git commit -m "$commit_msg"
        else
            # Stage and commit
            read -p "Stage all changes? (y/n): " stage_confirm
            if [[ "$stage_confirm" =~ ^[Yy]$ ]]; then
                git add -A
            else
                echo "Skipping staging. Only previously staged changes will be committed."
            fi
            
            read -p "Enter commit message: " commit_msg
            if [ -z "$commit_msg" ]; then
                commit_msg="Update $(date +%Y-%m-%d)"
            fi
            git commit -m "$commit_msg"
        fi
    fi
    
    # Sync before push
    if ! sync_before_push "origin"; then
        echo "❌ Sync failed - manual intervention required"
        cd ..
        return 1
    fi
    
    # Push
    echo "📤 Pushing to origin..."
    git push origin "$DEFAULT_BRANCH"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed to $repo_name"
    else
        echo ""
        echo "❌ Push failed for $repo_name"
        if [ "$auto_mode" = false ]; then
            echo ""
            echo "Options:"
            echo "  1) Force push (overwrites remote - DANGEROUS)"
            echo "  2) Skip this repo"
            read -p "Select option (1-2): " retry_opt
            case $retry_opt in
                1)
                    read -p "⚠️  Are you sure? This will overwrite remote! (yes/no): " force_confirm
                    if [ "$force_confirm" = "yes" ]; then
                        git push --force origin "$DEFAULT_BRANCH"
                        if [ $? -eq 0 ]; then
                            echo "✅ Force push successful"
                        else
                            echo "❌ Force push also failed"
                        fi
                    fi
                    ;;
            esac
        fi
    fi
    
    cd ..
}

# Push to both remotes (same local repo, different remotes)
do_push_both() {
    local github_url=$1
    local gitlab_url=$2
    local auto_mode=${3:-false}
    local commit_msg=${4:-""}
    local repo_name=$(basename "$github_url" .git)
    
    if [ ! -d "$repo_name" ]; then
        echo "❌ Directory '$repo_name' does not exist."
        return 1
    fi
    
    cd "$repo_name"
    
    # Show status
    echo ""
    echo "📊 Current status for $repo_name:"
    echo "─────────────────────────────────"
    git status -s
    echo ""
    
    # Check if there are changes
    if [ -z "$(git status --porcelain)" ]; then
        echo "No changes to commit."
        if [ "$auto_mode" = true ]; then
            echo "   Pushing any existing commits..."
        else
            read -p "Push existing commits anyway? (y/n): " push_anyway
            if [[ ! "$push_anyway" =~ ^[Yy]$ ]]; then
                cd ..
                return 0
            fi
        fi
    else
        if [ "$auto_mode" = true ]; then
            git add -A
            if [ -z "$commit_msg" ]; then
                commit_msg="Update $(date +%Y-%m-%d)"
            fi
            git commit -m "$commit_msg"
        else
            read -p "Stage all changes? (y/n): " stage_confirm
            if [[ "$stage_confirm" =~ ^[Yy]$ ]]; then
                git add -A
            fi
            
            read -p "Enter commit message: " commit_msg
            if [ -z "$commit_msg" ]; then
                commit_msg="Update $(date +%Y-%m-%d)"
            fi
            git commit -m "$commit_msg"
        fi
    fi
    
    # Ensure both remotes are configured
    echo ""
    echo "Configuring remotes..."
    git remote remove github 2>/dev/null
    git remote remove gitlab 2>/dev/null
    git remote add github "$github_url" 2>/dev/null
    git remote add gitlab "$gitlab_url" 2>/dev/null
    
    # Sync and push to GitHub
    echo ""
    echo "📤 Pushing to GitHub..."
    if sync_before_push "github"; then
        git push github "$DEFAULT_BRANCH"
        github_result=$?
    else
        echo "   ⚠️  Sync with GitHub failed, attempting push anyway..."
        git push github "$DEFAULT_BRANCH"
        github_result=$?
    fi
    
    # Sync and push to GitLab
    echo ""
    echo "📤 Pushing to GitLab..."
    if sync_before_push "gitlab"; then
        git push gitlab "$DEFAULT_BRANCH"
        gitlab_result=$?
    else
        echo "   ⚠️  Sync with GitLab failed, attempting push anyway..."
        git push gitlab "$DEFAULT_BRANCH"
        gitlab_result=$?
    fi
    
    echo ""
    if [ $github_result -eq 0 ] && [ $gitlab_result -eq 0 ]; then
        echo "✅ Successfully pushed to both remotes"
    else
        [ $github_result -ne 0 ] && echo "❌ GitHub push failed"
        [ $gitlab_result -ne 0 ] && echo "❌ GitLab push failed"
    fi
    
    cd ..
}

# Clone all repositories
clone_all() {
    echo ""
    echo "Select which repositories to clone:"
    echo "  1) All GitHub repos"
    echo "  2) All GitLab repos"
    echo "  3) All repos (both platforms)"
    echo ""
    read -p "Select option (1-3): " clone_choice
    
    case $clone_choice in
        1)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Cloning all GitHub repositories"
            echo "═══════════════════════════════════════"
            for repo in "${github_repos[@]}"; do
                echo ""
                do_clone "$repo" true
            done
            ;;
        2)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Cloning all GitLab repositories"
            echo "═══════════════════════════════════════"
            for repo in "${gitlab_repos[@]}"; do
                echo ""
                do_clone "$repo" true
            done
            ;;
        3)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Cloning all repositories"
            echo "═══════════════════════════════════════"
            echo ""
            echo "── GitHub ──"
            for repo in "${github_repos[@]}"; do
                echo ""
                do_clone "$repo" true
            done
            echo ""
            echo "── GitLab ──"
            for repo in "${gitlab_repos[@]}"; do
                echo ""
                do_clone "$repo" true
            done
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
}

# Fetch all repositories
fetch_all() {
    echo ""
    echo "Select which repositories to fetch:"
    echo "  1) All GitHub repos"
    echo "  2) All GitLab repos"
    echo "  3) All repos (both platforms)"
    echo ""
    read -p "Select option (1-3): " fetch_choice
    
    case $fetch_choice in
        1)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Fetching all GitHub repositories"
            echo "═══════════════════════════════════════"
            for repo in "${github_repos[@]}"; do
                echo ""
                do_fetch "$repo" true
            done
            ;;
        2)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Fetching all GitLab repositories"
            echo "═══════════════════════════════════════"
            for repo in "${gitlab_repos[@]}"; do
                echo ""
                do_fetch "$repo" true
            done
            ;;
        3)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Fetching all repositories"
            echo "═══════════════════════════════════════"
            echo ""
            echo "── GitHub ──"
            for repo in "${github_repos[@]}"; do
                echo ""
                do_fetch "$repo" true
            done
            echo ""
            echo "── GitLab ──"
            for repo in "${gitlab_repos[@]}"; do
                echo ""
                do_fetch "$repo" true
            done
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
}

# Push all repositories
push_all() {
    echo ""
    echo "Select which repositories to push:"
    echo "  1) All GitHub repos"
    echo "  2) All GitLab repos"
    echo "  3) All repos to both platforms (dual remote)"
    echo ""
    read -p "Select option (1-3): " push_choice
    
    read -p "Enter commit message for all repos (Enter for dated default): " batch_commit_msg
    if [ -z "$batch_commit_msg" ]; then
        batch_commit_msg="Update $(date +%Y-%m-%d)"
    fi
    
    case $push_choice in
        1)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Pushing all GitHub repositories"
            echo "═══════════════════════════════════════"
            for repo in "${github_repos[@]}"; do
                echo ""
                do_push "$repo" true "$batch_commit_msg"
            done
            ;;
        2)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Pushing all GitLab repositories"
            echo "═══════════════════════════════════════"
            for repo in "${gitlab_repos[@]}"; do
                echo ""
                do_push "$repo" true "$batch_commit_msg"
            done
            ;;
        3)
            echo ""
            echo "═══════════════════════════════════════"
            echo "  Pushing all repos to both platforms"
            echo "═══════════════════════════════════════"
            for i in "${!github_repos[@]}"; do
                echo ""
                do_push_both "${github_repos[$i]}" "${gitlab_repos[$i]}" true "$batch_commit_msg"
            done
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
}

# Display header
show_header() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║       Git Repository Manager          ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Current directory: $(pwd)"
    echo ""
}

# =============================================================================
# Main Menu Loop
# =============================================================================

while true; do
    show_header
    echo "What would you like to do?"
    echo "─────────────────────────────────────────"
    echo ""
    echo "  Single Repository:"
    echo "    1) Clone a repository"
    echo "    2) Fetch from a repository"
    echo "    3) Push to a repository"
    echo ""
    echo "  Batch Operations:"
    echo "    4) Clone ALL repositories"
    echo "    5) Fetch ALL repositories"
    echo "    6) Push ALL repositories"
    echo ""
    echo "    q) Quit"
    echo ""
    
    read -p "Select operation: " operation
    
    case $operation in
        1)
            # Clone single repo
            echo ""
            echo "Select platform to clone from:"
            echo "  1) GitHub"
            echo "  2) GitLab"
            echo ""
            read -p "Select platform (1-2): " platform
            
            case $platform in
                1)
                    if select_repo github_repos "GitHub"; then
                        do_clone "$selected_repo"
                    fi
                    ;;
                2)
                    if select_repo gitlab_repos "GitLab"; then
                        do_clone "$selected_repo"
                    fi
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
            ;;
        2)
            # Fetch single repo
            echo ""
            echo "Select platform to fetch from:"
            echo "  1) GitHub"
            echo "  2) GitLab"
            echo ""
            read -p "Select platform (1-2): " platform
            
            case $platform in
                1)
                    if select_repo github_repos "GitHub"; then
                        do_fetch "$selected_repo"
                    fi
                    ;;
                2)
                    if select_repo gitlab_repos "GitLab"; then
                        do_fetch "$selected_repo"
                    fi
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
            ;;
        3)
            # Push single repo
            echo ""
            echo "Push to which remote?"
            echo "  1) GitHub only"
            echo "  2) GitLab only"
            echo "  3) Both (same repo, dual remotes)"
            echo ""
            read -p "Select option (1-3): " push_option
            
            case $push_option in
                1)
                    if select_repo github_repos "GitHub"; then
                        do_push "$selected_repo"
                    fi
                    ;;
                2)
                    if select_repo gitlab_repos "GitLab"; then
                        do_push "$selected_repo"
                    fi
                    ;;
                3)
                    echo ""
                    echo "Select the repository to push to both remotes."
                    echo "(Assumes same repo name exists in both arrays)"
                    echo ""
                    
                    # List repos by name
                    echo "Available repositories:"
                    i=1
                    for repo in "${github_repos[@]}"; do
                        repo_name=$(basename "$repo" .git)
                        echo "  $i) $repo_name"
                        ((i++))
                    done
                    echo ""
                    
                    read -p "Select repository (1-${#github_repos[@]}): " selection
                    
                    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#github_repos[@]}" ]; then
                        idx=$((selection-1))
                        do_push_both "${github_repos[$idx]}" "${gitlab_repos[$idx]}"
                    else
                        echo "Invalid selection."
                    fi
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
            ;;
        4)
            clone_all
            ;;
        5)
            fetch_all
            ;;
        6)
            push_all
            ;;
        q|Q)
            echo ""
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
    
    echo ""
    echo "─────────────────────────────────────────"
    read -p "Press Enter to continue..."
done