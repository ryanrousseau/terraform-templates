#!/bin/bash

serverUrl="https://$1"   # The url of your Octopus server
serverCommsPort=443            # The communication port the Octopus Server is listening on (10943 by default)
apiKey=$2
spaceName=$3 #"White Rock Global" # The name of the space to register the Tentacle in
name=$HOSTNAME      # The name of the Tentacle at is will appear in the Octopus portal
environment=$4 #"Development"  # The environment to register the Tentacle in
rolesArg=$5   # The role to assign to the Tentacle
configFilePath="/etc/octopus/default/tentacle-default.config"
applicationPath="/home/Octopus/Applications/"
serverCommsAddress="https://polling.$1" #demo.octopus.app"
tenant=$6

IFS=',' read -r -a roles <<< "$rolesArg"

sudo apt update -y && sudo apt install -y --no-install-recommends gnupg curl ca-certificates apt-transport-https && \
sudo install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://apt.octopus.com/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/octopus.gpg && \
sudo chmod a+r /etc/apt/keyrings/octopus.gpg && \
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/octopus.gpg] https://apt.octopus.com/ \
  stable main" | \
  sudo tee /etc/apt/sources.list.d/octopus.list > /dev/null && \
sudo apt update -y && sudo apt install tentacle -y

/opt/octopus/tentacle/Tentacle create-instance --config "$configFilePath"
/opt/octopus/tentacle/Tentacle new-certificate --if-blank
/opt/octopus/tentacle/Tentacle configure --noListen True --reset-trust --app "$applicationPath"
echo "Registering the Tentacle $name with server $serverUrl in environment $environment with role $role"
/opt/octopus/tentacle/Tentacle register-with --server "$serverUrl" --apiKey "$apiKey" --space "$spaceName" --name "$name" --env "$environment" --comms-style "TentacleActive" --server-comms-port $serverCommsPort --server-comms-address $serverCommsAddress ${roles[@]/#/--role } ${tenant:+ --tenant $tenant} --tenanted-deployment-participation TenantedOrUntenanted
/opt/octopus/tentacle/Tentacle service --install --start