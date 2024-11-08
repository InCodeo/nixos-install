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
  networking.hostName = "nixos-client"; # Will be set during setup
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

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable KDE Plasma 6
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";    # Fallback to US layout to avoid keymap build issues
    xkbVariant = "";
  };

  # Configure console keymap
  console.useXkbConfig = true;  # Use X11 keyboard configuration for console

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable sound with pipewire
  sound.enable = true;          # Added explicit sound enable
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;         # Added JACK support
  };

  # Tailscale configuration
  services.tailscale.enable = true;

  # User configuration - additive approach
  users.users.homelab = {
    isNormalUser = true;
    description = "Home Lab User";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
    packages = with pkgs; [
      kdePackages.kate
    ];
    initialPassword = "changeme";
  };

  # Enable Firefox
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    wget
    vim
    git
    tailscale
    iptsd  # For touch screen support
    libwacom
    pciutils    # Added for hardware debugging
    usbutils    # Added for hardware debugging
    curl
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

  # Surface Pro specific configuration
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "surface_acpi=off"
      "mem_sleep_default=deep"
    ];
    # Added initrd modules for better hardware support
    initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
    initrd.kernelModules = [ "dm-snapshot" ];
  };

  # Enable firmware updates
  services.fwupd.enable = true;

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

# Function to get client number and set hostname
setup_hostname() {
    read -p "Enter client number (e.g., 1 for nixos-client-1): " client_num
    new_hostname="nixos-client-1"
    sed -i "s/networking.hostName = \"nixos-client\"/networking.hostName = \"$new_hostname\"/" /etc/nixos/configuration.nix
    echo "Hostname set to: $new_hostname"
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
    echo "Starting NixOS client setup..."
    
    # Backup existing configuration
    backup_configuration
    
    # Create configuration
    create_configuration
    
    # Validate configuration
    validate_configuration
    
    # Set hostname
    setup_hostname
    
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
        # Add a delay to allow services to start
        sleep 10
        # Ensure Tailscale is available after rebuild
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
    echo "Client hostname: $new_hostname"
    echo ""
    echo "Next steps:"
    echo "1. The managed user 'homelab' has been created with password 'changeme'"
    echo "   You will be prompted to change this password on first login"
    echo ""
    echo "2. To harden SSH security, run these commands from your controller:"
    echo "   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_client"
    if [ -n "$tailscale_ip" ]; then
        echo "   ssh-copy-id -i ~/.ssh/id_ed25519_client homelab@$tailscale_ip"
    else
        echo "   ssh-copy-id -i ~/.ssh/id_ed25519_client homelab@<your-tailscale-ip>"
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
    echo "   - Check for firmware issues: dmesg | grep -i firmware"
    echo "   - Your original configuration was backed up to $backup_file"
}

main