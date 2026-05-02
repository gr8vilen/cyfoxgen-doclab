#!/bin/bash

NETWORK_NAME="cyberlab_net"

# Detect default interface
PARENT_INTERFACE=$(ip route | grep default | awk '{print $5}')
echo "Detected interface: $PARENT_INTERFACE"

# Get IP details
IP_INFO=$(ip -4 addr show "$PARENT_INTERFACE" | grep inet | awk '{print $2}')
SUBNET=$(ipcalc -n "$IP_INFO" | grep Network | awk '{print $2}')
GATEWAY=$(ip route | grep default | awk '{print $3}')

echo "Detected Subnet: $SUBNET"
echo "Detected Gateway: $GATEWAY"

# Check if network already exists
if docker network inspect $NETWORK_NAME &> /dev/null; then
    echo "Network $NETWORK_NAME already exists"
else
    echo "Creating macvlan network..."
    docker network create -d macvlan \
      --subnet=$SUBNET \
      --gateway=$GATEWAY \
      -o parent=$PARENT_INTERFACE \
      $NETWORK_NAME
    echo "✅ Created macvlan network: $NETWORK_NAME"
fi
