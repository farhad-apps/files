#!/bin/bash

BASE_URL="{api_url}";
API_TOKEN="{api_token}";

server_ip=$(hostname -I | awk '{print $1}')

DATA=$(cat <<EOF
{
"username": "$username",
"user_ip": "$trusted_ip",
"pid": "$trusted_port",
"server_ip": "$server_ip",
"bytes_received": "$bytes_received",
"bytes_sent": "$bytes_sent",
"type": "$script_type"
}
EOF
    )
    
encodedData=$(echo -n "$DATA" | base64 -w 0)

if [ "$script_type" == "client-connect" ]; then
    apiUrl="${BASE_URL}/ovpn/uconnect?token=${API_TOKEN}"
else
    apiUrl="${BASE_URL}/ovpn/udisconnect?token=${API_TOKEN}"
fi

jsonData="{\"data\": \"$encodedData\"}"

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$jsonData" "$apiUrl")

if [ "$response" -eq  200 ]; then
    exit 0
else
    exit 1
fi
