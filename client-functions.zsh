# Reload ZSH configuration
function zsource() {
    echo "🔄 Reloading ZSH configuration..."
    source ~/.zshrc
    echo "✅ Done"
}

# Update all packages
function pkgup() {
    echo "📦 Updating system packages..."
    sudo nix-channel --update || { echo "❌ Channel update failed"; return 1; }
    sudo nixos-rebuild switch || { echo "❌ Rebuild failed"; return 1; }
    echo "✅ Done"
}

# System maintenance
function maintain() {
    echo "🧹 Running system maintenance..."
    echo "Cleaning old generations..."
    sudo nix-collect-garbage -d || { echo "❌ Garbage collection failed"; return 1; }
    echo "Optimizing store..."
    sudo nix-store --optimize || { echo "❌ Store optimization failed"; return 1; }
    echo "✅ Done"
} 