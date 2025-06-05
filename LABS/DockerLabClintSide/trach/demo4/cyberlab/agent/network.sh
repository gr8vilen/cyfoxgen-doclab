#!/bin/bash
set -e

ip link add lab_net link eth0 type macvlan mode bridge
ip addr add 192.168.100.1/24 dev lab_net
ip link set lab_net up
