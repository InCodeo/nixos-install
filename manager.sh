#!/bin/bash

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run as root"
        exit 1
    fi
}

# Function to backup existing configuration
backup_configuration() {
    if [ -f "/etc/nixos/configuration.nix" ]; then
        backup_file="/etc/nixos/configuration.nix.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/nixos/configuration.nix "$backup_file"
        echo "Backed up existing configuration to $backup_file"
    fi
}

# Function to create configuration.nix
create_configuration() {
    cat > /etc/nixos/configuration.nix << 'EOL'
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "nixos-manager"; # Define your hostname.
  networking.networkmanager.enable = true;

  # Time zone and locale settings
  time.timeZone = "Australia/Sydney";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_AU.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

  # Console configuration
  console = {
    keyMap = "us";
    packages = with pkgs; [ terminus_font ];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";
  };

  # Enable sound with pipewire
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Tailscale configuration
  services.tailscale.enable = true;

  # User configuration
  users.users.admin = {
    isNormalUser = true;
    description = "Management Admin";
    extraGroups = [ "networkmanager" "wheel" ];
    initialPassword = "changeme";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Management tools and basic system packages
  environment.systemPackages = with pkgs; [
    wget
    vim
    git
    tailscale
    colmena
    htop
    tmux
    iftop
    nmap
    curl
    pciutils
    usbutils
  ];

  # SSH Configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # Will be disabled after initial setup
      PermitRootLogin = "yes";       # Will be disabled after initial setup
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      22    # SSH
    ];
    # Allow Tailscale traffic
    trustedInterfaces = [ "tailscale0" ];
    # Allow incoming connections through Tailscale
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  system.stateVersion = "24.05";
}
EOL

    echo "Created configuration.nix"
}

# Function to validate configuration
validate_configuration() {
    echo "Validating configuration..."
    if ! nixos-rebuild build; then
        echo "Error: Configuration validation failed"
        echo "Would you like to restore the backup? (y/n)"
        read -r restore
        if [ "$restore" = "y" ]; then
            if [ -f "$backup_file" ]; then
                cp "$backup_file" /etc/nixos/configuration.nix
                echo "Restored previous configuration"
                exit 1
            else
                echo "No backup file found"
                exit 1
            fi
        fi
        exit 1
    fi
}

# Function to handle Tailscale setup
setup_tailscale() {
    echo "Would you like to set up Tailscale now? (y/n)"
    read -r setup_now
    
    if [ "$setup_now" = "y" ]; then
        echo "Please paste your Tailscale auth key (from https://login.tailscale.com/admin/settings/keys):"
        read -s auth_key
        echo
        
        # Save auth key securely
        echo "$auth_key" > /etc/nixos/tailscale-auth.key
        chmod 600 /etc/nixos/tailscale-auth.key
        chown root:root /etc/nixos/tailscale-auth.key
        
        # Add auth key file to configuration
        sed -i '/services.tailscale.enable = true;/a \ \ services.tailscale.authKeyFile = "\/etc\/nixos\/tailscale-auth.key";' /etc/nixos/configuration.nix
    else
        echo "Skipping Tailscale setup. You can configure it later."
    fi
}

# Function to handle errors during rebuild
handle_rebuild_error() {
    echo "Error during nixos-rebuild. Checking common issues..."
    
    # Check if hardware-configuration.nix exists
    if [ ! -f "/etc/nixos/hardware-configuration.nix" ]; then
        echo "hardware-configuration.nix is missing. Generating..."
        nixos-generate-config --root /
    fi
    
    # Try updating nixpkgs channel first
    echo "Updating nixpkgs channel..."
    nix-channel --update
    
    # Try rebuilding with --show-trace for better error output
    echo "Attempting rebuild with --show-trace..."
    nixos-rebuild switch --show-trace
}

# Main setup process
main() {
    check_root
    echo "Starting NixOS manager node setup..."
    
    # Backup existing configuration
    backup_configuration
    
    # Create configuration
    create_configuration
    
    # Validate configuration
    validate_configuration
    
    # Setup Tailscale
    setup_tailscale
    
    # Rebuild NixOS
    echo "Rebuilding NixOS..."
    if ! nixos-rebuild switch; then
        handle_rebuild_error
    fi
    
    # Set up Tailscale connection if configured
    if [ -f "/etc/nixos/tailscale-auth.key" ]; then
        echo "Waiting for Tailscale to connect..."
        sleep 10
        if command -v tailscale >/dev/null 2>&1; then
            systemctl start tailscaled
            sleep 5
            tailscale up
            sleep 5
            tailscale_ip=$(tailscale ip)
        else
            echo "Warning: Tailscale command not found."
            echo "Please run these commands after reboot:"
            echo "1. systemctl start tailscaled"
            echo "2. tailscale up"
        fi
    fi
    
    echo "Setup complete!"
    if [ -n "$tailscale_ip" ]; then
        echo "Your Tailscale IP is: $tailscale_ip"
    fi
    echo ""
    echo "Next steps:"
    echo "1. The admin user has been created with password 'changeme'"
    echo "   You will be prompted to change this password on first login"
    echo ""
    echo "2. To harden SSH security, run these commands from another machine:"
    echo "   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_manager"
    if [ -n "$tailscale_ip" ]; then
        echo "   ssh-copy-id -i ~/.ssh/id_ed25519_manager admin@$tailscale_ip"
    else
        echo "   ssh-copy-id -i ~/.ssh/id_ed25519_manager admin@<your-tailscale-ip>"
    fi
    echo ""
    echo "3. After setting up SSH keys, disable password authentication by running:"
    echo "   sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/nixos/configuration.nix"
    echo "   sed -i 's/PermitRootLogin \"yes\"/PermitRootLogin \"no\"/' /etc/nixos/configuration.nix"
    echo "   nixos-rebuild switch"
    echo ""
    echo "4. If you experience any issues after reboot:"
    echo "   - Check system logs: journalctl -xb"
    echo "   - Verify hardware detection: lspci -v"
    echo "   - Your original configuration was backed up to $backup_file"
}

main