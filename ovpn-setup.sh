#!/bin/bash

PORT="{ovpn_port}"
DOMAIN="{ovpn_domain}"
API_TOKEN="{api_token}"
API_URL="{api_url}"

install_dependencies(){
  apt-get install -y openvpn iptables ca-certificates gnupg
}

install_easyrsa(){
    wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz
    mkdir -p /etc/openvpn/easy-rsa
    tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa
    rm -f ~/easy-rsa.tgz
}

build_certificates(){
    chown -R root:root /etc/openvpn/easy-rsa/
    cd /etc/openvpn/easy-rsa
    ./easyrsa --batch init-pki >/dev/null
    ./easyrsa --batch build-ca nopass >/dev/null 2>&1
    ./easyrsa --batch --days=3650 build-server-full server nopass >/dev/null 2>&1
    openvpn --genkey --secret /etc/openvpn/ta.key
    cp /etc/openvpn/easy-rsa/pki/{ca.crt,issued/server.crt,private/server.key} /etc/openvpn/
}

openvpn_auth_files(){
    touch /etc/openvpn/ulogin.sh
    touch /etc/openvpn/umanager.sh

    local ulogin_file_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-ulogin.sh"
    local ulogin_file_path="/etc/openvpn/ulogin.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$ulogin_file_path" "$ulogin_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{o_api_token}|$API_TOKEN|g" "$ulogin_file_path"
        sed -i "s|{o_api_url}|$API_URL|g" "$ulogin_file_path"
    fi

    local uman_file_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-umanager.sh"
    local uman_file_path="/etc/openvpn/umanager.sh"
    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$uman_file_path" "$uman_file_url"

    if [ $? -eq 0 ]; then
        sed -i "s|{o_api_token}|$API_TOKEN|g" "$uman_file_path"
        sed -i "s|{o_api_url}|$API_URL|g" "$uman_file_path"
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

configure_client_conf(){
    
    local conf_url="https://raw.githubusercontent.com/farhad-apps/files/main/ovpn-client.conf"
    local conf_path="/etc/openvpn/myuser.txt"

    # Use curl to fetch content from the URL and save it to the output file
    curl -s -o "$conf_path" "$conf_url"

    if [ $? -eq 0 ]; then

        sed -i "s|{o_domain}|$DOMAIN|g" "$conf_path"
        sed -i "s|{o_port}|$PORT|g" "$conf_path"

        ca_file="/etc/openvpn/ca.crt"
        tls_file="/etc/openvpn/ta.key"

        ca_content=$(<"$ca_file")
        tls_content=$(<"$tls_file")

cat <<EOF >> "$conf_path"

<ca>
$ca_content
</ca>
<tls-auth>
$tls_content
</tls-auth>
EOF
    
    fi
}

configure_iptable(){
    # Get primary NIC device name
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    PROTOCOL="udp"
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
   systemctl daemon-reload
   systemctl enable openvpn
   systemctl start openvpn
   
   echo "OpenVPN Success Configuration"
}

install_dependencies
install_easyrsa
build_certificates
configure_server_conf
configure_client_conf
openvpn_auth_files
configure_iptable
configure_ip_forward
start_openvpn
