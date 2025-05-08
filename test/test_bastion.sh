#!/bin/bash

echo -e "\n\n\n-----------------------------------------------------------------------------------------------------------------"
echo "Running Test Case I: Connect to the bastion instance using the SSH private key provided to the automated test in the PUBLIC_INSTANCE_SSH_KEY secret"
echo "Command: 'ssh -i ./private_key ubuntu@"$PUBLIC_IP"'"
echo -e "-----------------------------------------------------------------------------------------------------------------"


OUTPUT=$(ssh -i ./private_key ubuntu@$PUBLIC_IP 'echo $SSH_CONNECTION')
if [ $? -ne "0" ]
then
  echo "$OUTPUT"
  echo -e "\n\nCould not connect to the bastion instance using the provided SSH key. Please make sure the instance is running, you've launched Ubuntu instances, and the corresponding public key was added to the '~/.ssh/authorized_keys' file in your bastion instance."
  exit 1
fi

if ! [ -n "$OUTPUT" ]
then
  echo -e "\n\nSuccessfully connected to your bastion instance, but the SSH_CONNECTION environment variable, which required to extract the instance's private IP address, does not exist."
  echo "Found: $OUTPUT"
  exit 1
fi

echo '✅ Test case I was completed successfully!'

echo -e "\n\n\n-----------------------------------------------------------------------------------------------------------------"
echo "Running Test Case II: Execute bastion_connect.sh without providing the KEY_PATH env var."
echo -e "-----------------------------------------------------------------------------------------------------------------"

bash bastion_connect.sh $PUBLIC_IP $PRIVATE_IP ls &> /dev/null

EXIT_CODE=$?

if [ "$EXIT_CODE" -ne "5" ]
then
  echo -e "\n\nExpected bastion_connect.sh to be exited with code 5\n"
  echo "But found: $EXIT_CODE"
  exit 1
fi

echo '✅ Test case II was completed successfully!'


echo -e "\n\n\n-----------------------------------------------------------------------------------------------------------------"
echo "Running Test Case III: Execute bastion_connect.sh without providing parameters"
echo -e "-----------------------------------------------------------------------------------------------------------------"

bash bastion_connect.sh &> /dev/null

EXIT_CODE=$?

if [ "$EXIT_CODE" -ne "5" ]
then
  echo -e "\n\nExpected bastion_connect.sh to be exited with code 5\n"
  echo "But found: $EXIT_CODE"
  exit 1
fi

echo '✅ Test case III was completed successfully!'


echo -e "\n\n\n-----------------------------------------------------------------------------------------------------------------"
echo "Running Test Case IV: Connect to the polybot instance through the bastion instance and execute"
echo "                      'curl localhost:8443' command (which should return a 200 status code)."
echo "Command: bastion_connect.sh $PUBLIC_IP $POLYBOT_PRIVATE_IP curl localhost:8443"
echo -e "-----------------------------------------------------------------------------------------------------------------"

export KEY_PATH=$(pwd)/private_key
OUTPUT=$(bash bastion_connect.sh $PUBLIC_IP $POLYBOT_PRIVATE_IP curl --silent --output /dev/null --write-out '%{http_code}' localhost:8443)

if [ $? -ne "0" ]
then
  echo "$OUTPUT"
  echo -e "\n\nThere may be issues with the connection to the bastion instance, the connection to the polybot instance through the bastion instance, or the execution of the provided command in the instance."
  exit 1
fi

if ! echo $OUTPUT | grep -q -P "200"
then
    echo -e "\n\nYour script was executed successfully, but the curl command returned a non-200 status code.\n"
    echo "That might indicate that the SSH connection is invalid, or your bastion_connect.sh script has connected using methods other than the default ssh client."
    exit 1
fi

echo '✅ Test case IV was completed successfully!'


echo -e "\n\n\n-----------------------------------------------------------------------------------------------------------------"
echo "Running Test Case V: Connect to the polybot instance through the bastion instance and execute"
echo "                      'curl YOLO_PRIVATE_IP:8080/health' command to talk to the YOLO instance (which should return a 200 status code)."
echo "Command: bastion_connect.sh $PUBLIC_IP $POLYBOT_PRIVATE_IP curl $YOLO_PRIVATE_IP:8080/health"
echo -e "-----------------------------------------------------------------------------------------------------------------"

export KEY_PATH=$(pwd)/private_key
OUTPUT=$(bash bastion_connect.sh $PUBLIC_IP $POLYBOT_PRIVATE_IP curl --silent --output /dev/null --write-out '%{http_code}' $YOLO_PRIVATE_IP:8080/health)

if [ $? -ne "0" ]
then
  echo "$OUTPUT"
  echo -e "\n\nThere may be issues with the connection to the bastion instance, the connection to the polybot instance through the bastion instance, or the execution of the provided command in the instance."
  exit 1
fi

if ! echo $OUTPUT | grep -q -P "200"
then
    echo -e "\n\nYour script was executed successfully, but the curl command returned a non-200 status code.\n"
    echo "That might indicate that the SSH connection is invalid, or your bastion_connect.sh script has connected using methods other than the default ssh client."
    exit 1
fi

echo '✅ Test case V was completed successfully!'

