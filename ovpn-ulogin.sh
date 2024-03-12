#!/bin/bash

BASE_URL="{api_url}";
API_TOKEN="{api_token}";

server_ip=$(hostname -I | awk '{print $1}')

DATA=$(cat <<EOF
{
"username": "$username",
"password": "$password"
}
EOF
  )

encodedData=$(echo -n "$DATA" | base64 -w 0)
apiUrl="${BASE_URL}/ovpn/ulogin?token=${API_TOKEN}"

jsonData="{\"data\": \"$encodedData\"}"

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$jsonData" "$apiUrl")

if [ "$response" -eq  200 ]; then
    exit 0
else
    exit 1
fi
