#!/bin/bash

ssh_port=22
udp_port=7300
api_token=""
api_url=""

echo "start" > /var/rocket-ssh/status.txt

read_config(){
    config_file="/var/rocket-ssh/rocket_config.txt"

    # Check if the config file exists
    if [ -f "$config_file" ]; then
        # Read the values using grep and awk
        ssh_port=$(grep '^ssh_port=' "$config_file" | awk -F= '{print $2}')
        udp_port=$(grep '^udp_port=' "$config_file" | awk -F= '{print $2}')
        api_token=$(grep '^api_token=' "$config_file" | awk -F= '{print $2}')
        api_url=$(grep '^api_url=' "$config_file" | awk -F= '{print $2}')
    fi
}

# Function to check and update needrestart configuration
config_needrestart() {
    local nrconf_file="/etc/needrestart/needrestart.conf"
    
    if [ -e "$nrconf_file" ]; then
        echo '$nrconf{restart} = "a";' >> "$nrconf_file"
    fi

}

# Function to install required packages
install_packages() {
    
    local packages=("build-essential" "libpam0g-dev" "libcurl4-openssl-dev" "cmake" "net-tools")
    
    sudo apt-get update

    for package in "${packages[@]}"; do
        sudo apt-get install -y "$package"
    done

}


# Function to install BadVPN using a script
setup_udpgw_service() {
   
    local username="videocall"

    if grep -q "^$username:" /etc/passwd; then
        echo "videocall is installed."
    else
        local vendorId=$(lscpu | awk -F': ' '/Vendor ID/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        if [ "$vendorId" = "ARM" ]; then
            sudo wget -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/mahmoud-ap/badvpn/master/udpgw-arm"
        else
            sudo wget -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/mahmoud-ap/badvpn/master/udpgw-x86"
        fi

        chmod 777 /usr/bin/badvpn-udpgw
        useradd -m videocall
    fi

    cat >  /etc/systemd/system/videocall.service << ENDOFFILE
[Unit]
Description=UDP forwarding for badvpn-tun2socks
After=nss-lookup.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:$udp_port --max-clients 999
User=videocall

[Install]
WantedBy=multi-user.target
ENDOFFILE

    systemctl enable videocall
    systemctl start videocall

    echo "videocall configured"
   
}

# Function to install Nethogs using a script
setup_nethogs() {
    bash <(curl -Ls https://raw.githubusercontent.com/mahmoud-ap/nethogs-json/master/install.sh --ipv4)
    wait
}


build_pam_file(){
 
    local file_url="https://raw.githubusercontent.com/farhad-apps/files/main/auth.c"
    # Define the name of the file you want to create
    local file_path="/lib/security/rocket_ssh_auth.c"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then

        sed -i "s|{api_token}|$api_token|g" "$file_path"
        sed -i "s|{api_url}|$api_url|g" "$file_path"

        # Compile the updated content (assuming it's a C file)
        compile_path="/lib/security/rocket_ssh_auth.so" 
        
        gcc -shared -o $compile_path -fPIC $file_path -lcurl -lpam -lpam_misc

        rm $file_path
    fi

}

# Function to configure PAM authentication
config_pam_auth() {
    
    local rocket_ssh_auth_file="/lib/security/rocket_ssh_auth.so"

    if [ -f "$rocket_ssh_auth_file" ]; then
  
        if ! sudo grep -q 'auth required rocket_ssh_auth.so$' /etc/pam.d/sshd; then
            echo "auth required rocket_ssh_auth.so" | sudo tee -a /etc/pam.d/sshd
        else
              echo "Not it auth required"
        fi
        
        if ! sudo grep -q 'session required rocket_ssh_auth.so$' /etc/pam.d/sshd; then
            echo "session required rocket_ssh_auth.so" | sudo tee -a /etc/pam.d/sshd
        fi
    fi

    sudo systemctl restart ssh
    sudo systemctl restart sshd
}

# Function to create a create rocketproc service
create_rocketproc_service(){
 
    local file_url="https://raw.githubusercontent.com/farhad-apps/files/main/rocketproc.sh"
    # Define the name of the file you want to create
    local file_path="/var/rocket-ssh/rocketproc.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$file_path" "$file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{api_token}|$api_token|g" "$file_path"
        sed -i "s|{api_url}|$api_url|g" "$file_path"
    fi

    chmod +x /var/rocket-ssh/rocketproc.sh

    cat >  /etc/systemd/system/rocketproc.service << ENDOFFILE
[Unit]
Description=Rocket Proccess
After=network.target

[Service]
ExecStart=/var/rocket-ssh/rocketproc.sh
WorkingDirectory=/var/rocket-ssh/
User=root
Restart=always

[Install]
WantedBy=multi-user.target
ENDOFFILE

    echo "rocketproc configured"
    sudo systemctl daemon-reload

}

# Function to configure a ssh 
config_sshd() {
  
    local rocket_sshd_file="/etc/ssh/rocket_sshd_config"
    if [ -f "$rocket_sshd_file" ]; then
        rm $rocket_sshd_file
    fi
    
    touch $rocket_sshd_file

    if ! grep -q "Include /etc/ssh/rocket_sshd_config" /etc/ssh/sshd_config; then
        echo "Include /etc/ssh/rocket_sshd_config" | sudo tee -a /etc/ssh/sshd_config
    fi

    sudo sed -i '/^#\s*Port 22/s/^#//' /etc/ssh/sshd_config

    if ! grep -qE '^\s*ClientAliveInterval' $rocket_sshd_file; then
         echo "ClientAliveInterval 60" | sudo tee -a $rocket_sshd_file
    fi

    if ! grep -qE '^\s*ClientAliveCountMax' $rocket_sshd_file; then
        echo "ClientAliveCountMax 2" | sudo tee -a $rocket_sshd_file
    fi

    if ! grep -qE "^\s*Port $ssh_port" $rocket_sshd_file; then
        echo "Port $ssh_port" | sudo tee -a $rocket_sshd_file
    fi

    sudo systemctl restart ssh
    sudo systemctl restart sshd

}

complete_install(){
    echo "complete" > /var/rocket-ssh/status.txt

    local conf_file_path="/var/rocket-ssh/rocket_config.txt"
    if [ -f "$so_file_path" ]; then
        rm $conf_file_path
    fi

    local nethogs_folder_path="/var/rocket-ssh/nethogs-json-master"
    if [ -d "$nethogs_folder_path" ]; then
        rm -R $nethogs_folder_path
    fi

    local coron_file_path="/var/rocket-ssh/cronjob.sh"
    if [ -f "$coron_file_path" ]; then
        sudo systemctl stop cron
        pkill -f /var/rocket-ssh/cronjob.sh 
        rm $coron_file_path
        rm /var/rocket-ssh/cronjob.lock
    fi

    local ssh_auth_file="/var/rocket-ssh/rocket_ssh_auth.so"
    if [ -f "$ssh_auth_file" ]; then
        rm $ssh_auth_file
    fi

    sleep 5
    
    systemctl enable rocketproc
    systemctl start rocketproc
    
    # Remove the script file
    rm /var/rocket-ssh/install
    rm /usr/bin/jcurl.sh
}


# Call the functions to perform the tasks
config_needrestart
install_packages
read_config
setup_nethogs
setup_udpgw_service
build_pam_file
config_pam_auth
config_sshd
create_rocketproc_service
complete_install
