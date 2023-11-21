#!/bin/bash

apiBaseUrl="{api_url}"
apiToken="{api_token}"

run_nethogs_and_send_to_api() {
    
    local filePath="/var/rocket-ssh/nethogs_output.json"
    
    # Run nethogs and capture output in a file
    nethogs -v3 -c6 -j > "$filePath"
    
    # Read the content of the file
    sleep 1
    nethogsContent=$(cat "$filePath")
 
    # Send content to API
    if [ -n "$nethogsContent" ]; then
        encodedData=$(echo -n "$nethogsContent" | base64 -w 0)

        local apiUrl="${apiBaseUrl}/traffics?token=${apiToken}"

        jsonData="{\"data\": \"$encodedData\"}"

        curl -X POST -H "Content-Type: application/json" -d "$jsonData" "$apiUrl"

        # Remove the file
        rm "$filePath"

    fi
}

create_user_banner(){
    local EXCLUDE_USERS=("videocall" "sshd")

    for user_dir in /home/*; do
        # Check if the item in /home is a directory
        if [ -d "$user_dir" ]; then
            # Extract the username from the directory path
            username=$(basename "$user_dir")
            # Check if the username is in the exclusion list
            if [[ " ${EXCLUDE_USERS[*]} " != *"$username"* ]]; then

                local apiUrl="${apiBaseUrl}/ubanner?token=${apiToken}&username=$username"

                local api_response=$(curl -s GET "$apiUrl")

                local html_file="/var/ssh-banners/${username}"

                if [ -e "$html_file" ]; then
                   rm "$html_file"
                fi

                echo "$api_response" >> "$html_file"

                sleep 0.5

            fi
        fi
    done
}

send_system_resources(){
    # Function to get CPU information
    CPU_INFO=$(lscpu)
    CPU_NAME=$(echo "$CPU_INFO" | grep "Model name" | cut -d: -f2 | sed 's/^[[:space:]]*//')
    CPU_CORES=$(nproc)
    CPU_USAGE=$(top -bn1 | grep "%Cpu(s)" | awk '{print $2}')
    CPU_LOAD=$(uptime | awk -F 'load average: ' '{print $2}' | awk -F, '{print $1}')

    # Function to get memory information
    MEMORY_INFO=$(free)
    TOTAL_RAM=$(echo "$MEMORY_INFO" | grep "Mem:" | awk '{print $2}')
    USED_RAM=$(echo "$MEMORY_INFO" | grep "Mem:" | awk '{print $3}')
    FREE_RAM=$(echo "$MEMORY_INFO" | grep "Mem:" | awk '{print $4}')
    AVAIL_RAM=$(echo "$MEMORY_INFO" | grep "Mem:" | awk '{print $6}')

    # Function to get disk information
    DISK_INFO=$(df -h /)
    TOTAL_HDD=$(echo "$DISK_INFO" | grep "/dev/" | awk '{print $2}')
    USED_HDD=$(echo "$DISK_INFO" | grep "/dev/" | awk '{print $3}')
    AVAIL_HDD=$(echo "$DISK_INFO" | grep "/dev/" | awk '{print $4}')
    USED_PHDD=$(echo "$DISK_INFO" | grep "/dev/" | awk '{print $5}')


    # Function to get system uptime
    UPTIME=$(uptime -p)

    # Prepare the data for API
    DATA=$(cat <<EOF
    {
    "cpu_name": "$CPU_NAME",
    "cpu_cores": "$CPU_CORES",
    "cpu_usage": "$CPU_USAGE",
    "cpu_load": "$CPU_LOAD",
    "total_ram": "$TOTAL_RAM",
    "used_ram": "$USED_RAM",
    "free_ram": "$FREE_RAM",
    "avail_ram": "$AVAIL_RAM",
    "total_hdd": "$TOTAL_HDD",
    "used_hdd": "$USED_HDD",
    "avail_hdd": "$AVAIL_HDD",
    "used_phdd": "$USED_PHDD",
    "uptime": "$UPTIME"
    }
EOF
    )

    local apiUrl="${apiBaseUrl}/resources?token=${apiToken}"
    # Send the data to the API using 'curl' (you may need to install curl if it's not already installed)
    curl -X POST -H "Content-Type: application/json" -d "$DATA" "$apiUrl"
}

while true; do
    run_nethogs_and_send_to_api
    sleep 5
done &

while true; do
    create_user_banner
    sleep 600
done &

while true; do
    send_system_resources
    sleep 120
done &

while true; do
    service ssh restart
    service sshd restart
    sleep 1800
done
