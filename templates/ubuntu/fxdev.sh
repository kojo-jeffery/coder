#!/bin/bash

set -o errexit
set -o nounset

PACKAGES="node openvpn3 gcloud starship redis-server terraform ansible nvim"
LOG_FILE="$HOME/installation_log.txt"

function run_pre_installs() {
  cd $HOME
  sudo apt update & spinner 
  wait $! 
  sudo apt --yes upgrade 
  sudo apt --yes --no-install-recommends install net-tools htop build-essential software-properties-common
}

function run_autoremove() {
  sudo apt autoremove --yes
}

function run_cleanup() {
  sudo apt clean
}

function run_term_apps() {
  sudo apt --yes install curl bash make git tmux neofetch vim fzf ripgrep fd-find jq & spinner
  wait $! 
}

function cleanup_cache() {
  CACHE_DIR="$HOME/.install_cache"
  CACHE_INDEX="$CACHE_DIR/.index"
  MAX_CACHE_SIZE="1G" 

  cache_size=$(du -sb "$CACHE_DIR" | cut -f1)

  if [[ $cache_size -gt $(numfmt --from=iec $MAX_CACHE_SIZE) ]]; then
     echo "Cache size exceeds limit. Cleaning up..."

     # Read installers from CACHE_INDEX and delete 
     if [ -f "$CACHE_INDEX" ]; then
         while IFS= read -r installer; do  
             filePath="$CACHE_DIR/$installer"
             if [ -f "$filePath" ]; then
                 rm "$filePath" || log "Failed to delete $filePath"

                 # Remove the entry from CACHE_INDEX (enhanced)
                 sed -i "/^$installer/d" "$CACHE_INDEX" || log "Failed to update CACHE_INDEX"
             fi
         done < "$CACHE_INDEX"
     fi
  fi
}

function spinner() {
  local pid=$!
  local spinchars='-\|/\\'
  local delay=0.1
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    for char in $spinchars; do
      echo -ne "\b$char"
      sleep $delay
    done
  done
  echo -ne "\b " 
}

function log() {
  local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  local message="$1"
  echo "[${timestamp}] - ${message}" >> "$LOG_FILE" 
}

# SERVICES (installation functions with confirmation and log)
function install_node() {
  read -p "Install Node.js? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Node.js (via NVM)"

    # Install NVM (using latest version)
    if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash || { 
            log "NVM installation failed." 
            exit 1 
        }

        # Load NVM (adjust if your shell config is different)
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  

    else
        log "NVM already installed."
    fi

    # Install Node.js 18 LTS
    nvm install 18 || { log "Failed to install Node.js 18 LTS." ; exit 1; }

    # Set Node.js 18 LTS as default
    nvm use 18 || { log "Failed to set Node.js 18 LTS as default." ; exit 1; }

    log "Node.js (v18 LTS) installed successfully via NVM"
  else
    log "Skipping Node.js installation"
  fi
}

function install_openvpn3() {
  read -p "Install OpenVPN-3? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Starting OpenVPN-3 installation"

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    OPENVPN_DEB="openvpn3-release_2.4.6-1_amd64.deb"

    if [ -f "$CACHE_INDEX" ]; then
        installer_file=$(grep "^openvpn3:$OPENVPN_DEB" "$CACHE_INDEX")
        if [[ -n $installer_file ]]; then
            log "Using cached OpenVPN-3 installer" 
            sudo dpkg -i "$installer_file" || { log "OpenVPN-3 installation failed"; exit 1; }
        else 
            download_and_install_openvpn
        fi
    else
        touch "$CACHE_INDEX" 
        download_and_install_openvpn
    fi

    log "OpenVPN-3 installation successful"
  else
    log "Skipping OpenVPN-3 installation" 
  fi
}

function download_and_install_openvpn() {
    # Retry for downloading the installer
    MAX_RETRIES=3
    retry_count=0
    until curl -sL https://swupdate.openvpn.org/repos/openvpn3/$(lsb_release -cs)/main/$OPENVPN_DEB -o "$CACHE_DIR/$OPENVPN_DEB"; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Failed to download OpenVPN-3 installer after multiple attempts."
            return 1
        fi
        log "Download failed. Retrying in 5 seconds..."
        sleep 5
    done

    sudo dpkg -i "$CACHE_DIR/$OPENVPN_DEB" || { log "OpenVPN-3 installation failed"; exit 1; }

    sudo mkdir -p /etc/apt/keyrings 

    # Retry for downloading the keyring
    MAX_RETRIES=3
    retry_count=0
    until curl -fsSL https://packages.openvpn.net/packages-repo.gpg | sudo tee /etc/apt/keyrings/openvpn.asc; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Failed to download OpenVPN keyring after multiple attempts."
            return 1
        fi
        log "Keyring download failed. Retrying in 5 seconds..."
        sleep 5
    done

    sudo echo "deb [signed-by=/etc/apt/keyrings/openvpn.asc] https://packages.openvpn.net/openvpn3/debian $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/openvpn-packages.list

    # Retry for apt-get update
    MAX_RETRIES=3
    retry_count=0
    until sudo apt-get update; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Failed to update package lists after multiple attempts."
            return 1
        fi
        log "apt-get update failed. Retrying in 5 seconds..."
        sleep 5
    done

    sudo apt-get install openvpn3 -y  || echo {"Failed to install OpenVPN-3"}

    echo "openvpn3:$OPENVPN_DEB" >> "$CACHE_INDEX" 
}

function install_gcloud() {
  read -p "Install Google CLI? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Google CLI..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Check if repository is already configured
    if ! grep -q "packages.cloud.google.com" /etc/apt/sources.list.d/*; then
        log "Adding Google Cloud repository..."

        # Retries for apt-get update 
        MAX_RETRIES=3
        retry_count=0
        until sudo apt-get update; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to update package lists after multiple attempts."
                return 1
            fi
            log "apt-get update failed. Retrying in 5 seconds..."
            sleep 5 
        done

        # Retry for installing dependencies
        MAX_RETRIES=3
        retry_count=0
        until sudo apt-get install apt-transport-https ca-certificates gnupg curl sudo -y; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to install dependencies after multiple attempts."
                return 1
            fi
            log "Dependency installation failed. Retrying in 5 seconds..."
            sleep 5 
        done

        # Potential caching: Save the downloaded keyring
        if [ ! -f "$CACHE_DIR/cloud.google.gpg" ]; then
            # Retry for keyring download 
            MAX_RETRIES=3 
            retry_count=0
            until curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o "$CACHE_DIR/cloud.google.gpg"; do
                retry_count=$((retry_count + 1))
                if [[ $retry_count -ge $MAX_RETRIES ]]; then
                    log "Failed to download Google Cloud keyring after multiple attempts."
                    return 1 
                fi
                log "Keyring download failed. Retrying in 5 seconds..."
                sleep 5 
            done
        fi
        sudo cp "$CACHE_DIR/cloud.google.gpg" /usr/share/keyrings/cloud.google.gpg || { log "Failed to copy keyring."; exit 1; }

        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        echo "google-cloud-sdk:cloud.google.gpg" >> "$CACHE_INDEX"  # Add to index
    fi

    sudo apt-get install google-cloud-cli -y || { log "Google Cloud CLI installation failed."; exit 1; }

    log "Google CLI installed successfully"

    # Google Credentials Setup (If file exists)
  if [ -f "$GOOGLE_CLOUD_CREDENTIALS" ]; then 
    gcloud auth activate-service-account --key-file "$GOOGLE_CLOUD_CREDENTIALS" || { log "Failed to activate service account." }
    gcloud config set project "$GOOGLE_CLOUD_PROJECT" || { log "Failed to set default project." }

    log "Google Cloud credentials loaded and default project set."
  fi  # Close Google Credentials setup 
fi  # Close the initial if [[ $confirm == [yY] ]] 
else
  log "Skipping Google CLI installation."
fi
}

function install_starship() {
  read -p "Install Starship? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Starship..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Determine the appropriate Starship binary filename based on OS and architecture
    UNAME=$(uname | tr '[:upper:]' '[:lower:]')  # Normalize OS name
    ARCH=$(uname -m)
    if [[ $ARCH == "x86_64" ]]; then
        ARCH="x86-64" # Adjust if needed
    fi
    STARSHIP_BINARY="starship-$UNAME-$ARCH" 

    if [ -f "$CACHE_INDEX" ]; then
        installer_file=$(grep "^starship:$STARSHIP_BINARY" "$CACHE_INDEX")
        if [[ -n $installer_file ]]; then
            log "Using cached Starship binary"  # Log usage 
            sudo cp "$installer_file" /usr/local/bin/starship || { log "Failed to install Starship from cache."; exit 1; } 
            chmod +x /usr/local/bin/starship 
        else 
            download_and_install_starship
        fi
    else
        touch "$CACHE_INDEX" 
        download_and_install_starship
    fi

    log "Starship installed successfully!" 
  else
    log "Skipping Starship installation."
  fi
}

function download_and_install_starship() {
    MAX_RETRIES=3
    retry_count=0
    until curl -sS https://starship.rs/install.sh | sudo sh -s -- -y -B /usr/local/bin/starship; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Starship download or installation failed after multiple attempts."
            exit 1
        fi
        log "Starship download or installation failed. Retrying in 5 seconds..."
        sleep 5
    done
    echo "starship:$STARSHIP_BINARY" >> "$CACHE_INDEX" 
}

function install_redis_server() {
  read -p "Install Redis? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Redis..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Check if Redis repository is configured
    if ! grep -q "packages.redis.io" /etc/apt/sources.list.d/*; then
        log "Adding Redis repository..."

        # Retry for installing dependencies
        MAX_RETRIES=3 
        retry_count=0
        until sudo apt install lsb-release curl gpg -y; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to install dependencies after multiple attempts."
                return 1
            fi
            log "Dependency installation failed. Retrying in 5 seconds..."
            sleep 5 
        done

        # Potential caching: Save the downloaded keyring
        if [ ! -f "$CACHE_DIR/redis-archive-keyring.gpg" ]; then
            # Retry for keyring download 
            MAX_RETRIES=3 
            retry_count=0
            until curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o "$CACHE_DIR/redis-archive-keyring.gpg"; do
                retry_count=$((retry_count + 1))
                if [[ $retry_count -ge $MAX_RETRIES ]]; then
                    log "Failed to download Redis keyring after multiple attempts."
                    return 1 
                fi
                log "Keyring download failed. Retrying in 5 seconds..."
                sleep 5 
            done
        fi
        sudo cp "$CACHE_DIR/redis-archive-keyring.gpg" /usr/share/keyrings/redis-archive-keyring.gpg || { log "Failed to copy keyring."; exit 1; }

        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
        echo "redis:redis-archive-keyring.gpg" >> "$CACHE_INDEX" # Add to index

        # Retry for apt-get update
        MAX_RETRIES=3 
        retry_count=0
        until sudo apt-get update; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to update package lists after multiple attempts."
                return 1
            fi
            log "apt-get update failed. Retrying in 5 seconds..."
            sleep 5 
        done
    fi

    sudo apt-get install redis -y || { log "Redis installation failed."; exit 1; }

    sudo systemctl enable redis-server || { log "Failed to enable Redis service."; exit 1; } 
    sudo service redis-server start 
    sudo service redis-server status

    # Advanced Check: Verify Redis server functionality
    if ! redis-cli ping >/dev/null 2>&1; then
        log "Redis server seems to be down or inaccessible. Please check manually."
    else
        log "Redis server is running."
    fi

    log "Redis installed successfully" 
  else
    log "Skipping Redis installation."
  fi
}

function install_terraform() {
  read -p "Install Terraform? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Terraform..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Check if Terraform repository is configured
    if ! grep -q "apt.releases.hashicorp.com" /etc/apt/sources.list.d/*; then
        log "Adding Terraform repository..."

        # Retries for apt-get update
        MAX_RETRIES=3 
        retry_count=0
        until sudo apt-get update; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to update package lists after multiple attempts."
                return 1
            fi
            log "apt-get update failed. Retrying in 5 seconds..."
            sleep 5 
        done

        sudo apt-get install -y gnupg software-properties-common || { log "Failed to install dependencies."; exit 1; }

        # Potential caching: Save the downloaded keyring
        if [ ! -f "$CACHE_DIR/hashicorp.gpg" ]; then
            # Retry for keyring download
            MAX_RETRIES=3 
            retry_count=0
            until curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/hashicorp.gpg --import; do
                retry_count=$((retry_count + 1))
                if [[ $retry_count -ge $MAX_RETRIES ]]; then
                    log "Failed to import Terraform keyring after multiple attempts. Possible causes:"
                    log "- Network problems"
                    log "- GPG configuration issues"
                    log "Check the logs for more details."
                    return 1 
                fi
                log "Keyring download failed. Retrying in 5 seconds..."
                sleep 5 
            done

            sudo cp gnupg-ring:/etc/apt/trusted.gpg.d/hashicorp.gpg "$CACHE_DIR/hashicorp.gpg"  
        else
            sudo cp "$CACHE_DIR/hashicorp.gpg" gnupg-ring:/etc/apt/trusted.gpg.d/hashicorp.gpg || { log "Failed to copy keyring."; exit 1; }
        fi

        sudo chmod 644 /etc/apt/trusted.gpg.d/hashicorp.gpg
        echo "deb [signed-by=/etc/apt/trusted.gpg.d/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        echo "terraform:hashicorp.gpg" >> "$CACHE_INDEX" # Add to index
    fi

    sudo apt install terraform || { 
      log "Terraform installation failed. Possible causes:"
      log "- Network issues"
      log "- Incorrect repository configuration"
      log "Check the logs for more details."
      exit 1; 
  }

    terraform --version
    log "Terraform installed successfully" 
  else
    log "Skipping Terraform installation."
  fi
}

function install_ansible() {
  read -p "Install Ansible? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Ansible..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Check if Ansible repository is configured
    if ! grep -q "^ppa:ansible/ansible" /etc/apt/sources.list.d/*; then 
        echo "Adding Ansible repository..."

        # Retries for apt-get update
        MAX_RETRIES=3
        retry_count=0
        until sudo apt-get update; do
            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $MAX_RETRIES ]]; then
                log "Failed to update package lists after multiple attempts."
                return 1
            fi
            log "apt-get update failed. Retrying in 5 seconds..."
            sleep 5 
        done

        # Dependency Check
        if ! dpkg -s software-properties-common >/dev/null 2>&1; then
            sudo apt-get install -y software-properties-common || { log "Failed to install software-properties-common"; return 1; }
        fi

        # Retry for adding repository (if you deem this necessary)
        sudo apt-add-repository --yes --update ppa:ansible/ansible || { log "Failed to add Ansible repository."; return 1; }
        echo "ansible:ppa:ansible/ansible" >> "$CACHE_INDEX" # Add to cache index
    fi

    sudo apt-get install -y ansible ||  { log "Ansible installation failed."; return 1; }

    log "Ansible installed successfully" 
  else
    log "Skipping Ansible installation."
  fi
}

function install_neovim() {
  read -p "Install Neovim Latest? (y/n) " confirm
  if [[ $confirm == [yY] ]]; then
    log "Installing Neovim Latest..."

    CACHE_DIR="$HOME/.install_cache"
    CACHE_INDEX="$CACHE_DIR/.index"
    mkdir -p $CACHE_DIR

    # Check dependencies before building
    check_neovim_dependencies || { log "Missing Neovim dependencies. Installation aborted."; return 1; }

    # Neovim Build with Retries
    if [ ! -d "$HOME/neovim/build" ]; then
        cd $HOME
        download_and_install_neovim || { log "Failed to install Neovim."; return 1; }
    else
        log "Neovim already built. Skipping build process."
    fi

    # LazyVim Installation with Retries
    if [ ! -d "$HOME/.config/nvim" ]; then
        log "Installing LazyVim..."
        download_and_install_lazyvim || { log "Failed to install LazyVim."; return 1; }
    else
        log "LazyVim already installed."
    fi

    nvim --version 
    log "Neovim Latest installed successfully." 
  else
    log "Skipping Neovim installation."
  fi
}
function install_nvim(){
  install_neovim
}

function check_neovim_dependencies() {
    DEPS="ninja-build gettext cmake unzip curl ripgrep"
    for dep in $DEPS; do
        if ! command -v $dep >/dev/null 2>&1; then
            log "Missing dependency: $dep. Please install it first." 
            return 1
        fi
    done
}

function download_and_install_neovim() {
    MAX_RETRIES=3
    retry_count=0
    until git clone https://github.com/neovim/neovim && git checkout stable; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Failed to clone Neovim repository after multiple attempts."
            return 1
        fi
        log "Git clone failed. Retrying in 5 seconds..."
        sleep 5  # Wait before retrying
    done

    cd neovim
    make CMAKE_BUILD_TYPE=RelWithDebInfo VERBOSE=1 || { log "Failed to build Neovim."; return 1; }
    sudo make install VERBOSE=1 || { log "Failed to install Neovim."; return 1; }
}

function download_and_install_lazyvim() {
    MAX_RETRIES=3
    retry_count=0
    until git clone --depth 1 https://github.com/LazyVim/LazyVim.git "$HOME/.config/nvim"; do
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            log "Failed to install LazyVim after multiple attempts."
            return 1
        fi
        log "Git clone failed. Retrying in 5 seconds..."
        sleep 5 
    done
    nvim +Lazy +qall 
}

# Main menu function
function show_menu() {
  echo "-------------------- Installer Menu --------------------"
  echo "1. Install Node.js"
  echo "2. Install OpenVPN-3"
  echo "3. Install Google CLI (gcloud)"
  echo "4. Install Starship"
  echo "5. Install Redis"
  echo "6. Install Terraform"
  echo "7. Install Ansible"
  echo "8. Install Neovim"
  echo "9. Install All Packages"
  echo "0. Exit"
  echo "--------------------------------------------------------"
}

# Helper for Confirmation 
function confirm() {
    read -r -p "${1:-Are you sure?} (y/N) " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# STARTING SCRIPT
function main() {
  printf '\nInstalling pre-requisites...\n'
  run_pre_installs || exit 1
  run_term_apps || exit 1

  printf '\nRunning cleanups...\n'
  run_autoremove 
  run_cleanup

  # Installer Menu Loop
  while true; do
    show_menu
    read -p "Enter your choice (0 to Exit): " choice

    # Input Validation
    if [[ ! $choice =~ ^[0-9]+$ ]]; then 
        echo "Invalid option. Please enter a number."
        continue
    fi

    # Choice Handling (with confirmation)
    case $choice in
      1) install_node ;;
      2) install_openvpn3 ;;
      3) install_gcloud ;;
      4) install_starship ;;
      5) install_redis_server ;;
      6) install_terraform ;;
      7) install_ansible ;;
      8) install_neovim ;;
      9) confirm "Install all packages" && for pkg in $PACKAGES; do install_$pkg; done ;; 
      0) echo "Exiting installer. Goodbye!"
         exit 0 ;;
      *) echo "Invalid option. Please try again." ;;
    esac
  done

  cleanup_cache
  printf '\nInstallation completed successfully!\n'
}

# BOOT
main
