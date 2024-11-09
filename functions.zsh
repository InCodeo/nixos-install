# Shared git update function
function _nix_update_git() {
    local repo_path="$1"
    cd "$repo_path" || return 1
    git pull origin main || return 1
    return 0
}

# Local system update
function nixup() {
    echo "🔄 Updating NixOS configuration..."
    if _nix_update_git "/etc/nixos"; then
        echo "🔨 Rebuilding NixOS..."
        sudo nixos-rebuild switch || { echo "❌ Build failed"; return 1; }
        echo "✅ Done"
    else
        echo "❌ Git update failed"
        return 1
    fi
}

# Fleet deployment
function nixdeploy() {
    echo "🔄 Updating fleet configuration..."
    if _nix_update_git "/etc/nixos/fleet"; then
        echo "🚀 Deploying to fleet..."
        cd "/etc/nixos/fleet" && colmena apply || { echo "❌ Deploy failed"; return 1; }
        echo "✅ Done"
    else
        echo "❌ Git update failed"
        return 1
    fi
} 