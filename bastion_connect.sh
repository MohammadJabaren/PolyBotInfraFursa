#!/bin/bash


# Check if the KEY_PATH environment variable is set
if [ -z "$KEY_PATH" ]; then
    echo "KEY_PATH env var is expected"
    exit 5
fi

# Check if Bastion IP is not provided as an argument
if [ -z "$1" ]; then
    echo "Please provide bastion IP address"
    exit 5
fi

BASTION_IP=$1

# Case 2: connect to bastion only
if [ $# -eq 1 ]; then
  ssh -i "$KEY_PATH" -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$BASTION_IP"
  exit $?
fi

PRIVATE_IP=$2
shift 2

# Remaining arguments are optional command
REMOTE_CMD="$*"

if [ -z "$REMOTE_CMD" ]; then
  ssh -i "$KEY_PATH" -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$BASTION_IP" \
    ssh -i Jabaren_PolyBot_VM.pem -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$PRIVATE_IP"

else
  ssh -i "$KEY_PATH" -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$BASTION_IP" \
    ssh -i Jabaren_PolyBot_VM.pem -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$PRIVATE_IP" "$REMOTE_CMD"
fi
