#!/bin/bash

PORT="{ovpn_port}"

install_dependencies(){
  apt-get install -y openvpn iptables ca-certificates
}

install_easyrsa(){
    wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz
    mkdir -p /etc/openvpn/easy-rsa
    tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa
    rm -f ~/easy-rsa.tgz
}

build_certificates(){
    cd /etc/openvpn/easy-rsa
    ./easyrsa init-pki
    yes | ./easyrsa build-ca nopass
    ./easyrsa gen-dh
    yes | ./easyrsa build-server-full server nopass
    openvpn --genkey --secret pki/ta.key
    cp /etc/openvpn/easy-rsa/pki/{ca.crt,ta.key,issued/server.crt,private/server.key,dh.pem} "/etc/openvpn/"
    cd /etc/openvpn
}

openvpn_auth_files(){
    touch /etc/openvpn/ulogin.sh
    touch /etc/openvpn/umanager.sh

    local ulogin_file_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-ulogin.sh"
    local ulogin_file_path="/etc/openvpn/ulogin.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$ulogin_file_path" "$ulogin_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{api_token}|$api_token|g" "$file_path"
        sed -i "s|{api_url}|$api_url|g" "$file_path"
    fi

    local uman_file_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-umanager.sh"
    local uman_file_path="/etc/openvpn/ulogin.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$uman_file_path" "$uman_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{api_token}|$api_token|g" "$uman_file_path"
        sed -i "s|{api_url}|$api_url|g" "$uman_file_path"
    fi

    chmod +x /etc/openvpn/ulogin.sh
    chmod +x /etc/openvpn/umanager.sh

}

configure_server_conf(){
    mkdir /etc/openvpn/ccd

    local conf_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-server.conf"
    local conf_path="/etc/openvpn/server.conf"

    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$conf_path" "$conf_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{port}|$PORT|g" "$conf_path"
    fi
}

configure_iptable(){
    # Get primary NIC device name
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
echo "#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/openvpn/add-iptables-rules.sh

# Script to remove rules
echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/openvpn/rm-iptables-rules.sh

echo "[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/openvpn/add-iptables-rules.sh
ExecStop=/etc/openvpn/rm-iptables-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-openvpn.service

    chmod +x /etc/openvpn/add-iptables-rules.sh
    chmod +x /etc/openvpn/rm-iptables-rules.sh

    systemctl daemon-reload
    systemctl enable iptables-openvpn
    systemctl start iptables-openvpn
}

configure_ip_forward(){
    # Make ip forwading and make it persistent
    echo 1 > "/proc/sys/net/ipv4/ip_forward"
    echo "net.ipv4.ip_forward = 1" >> "/etc/sysctl.conf"
}

start_openvpn(){
    systemctl enable openvpn
    systemctl start openvpn

    echo "OpenVPN Success Configuration"
}

install_dependencies
install_easyrsa
build_certificates
configure_server_conf
openvpn_auth_files
configure_iptable
configure_ip_forward
start_openvpn
