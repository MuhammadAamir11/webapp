#!/bin/bash

#1 create resource group
az group create --name MVCAppRG --location northeurope

#2 create VM
az vm create \
  --resource-group MVCAppRG \
  --name MVCAppVM \
  --image Ubuntu2204 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --size Standard_B1s

#3 fetch Public IP adress and openOpen Port 5000 on the Azure VM 
PUBLIC_IP=$(az vm show -d -g MVCAppRG -n MVCAppVM --query publicIps -o tsv)
echo "VM Public IP: $PUBLIC_IP"

az vm open-port --resource-group MVCAppRG --name MVCAppVM --port 5000 --priority 890


#4 Install .NET SDK & Runtime on Azure VM
ssh -o StrictHostKeyChecking=no azureuser@$PUBLIC_IP << 'EOF'
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    sudo apt-get update -y
    sudo apt-get install -y dotnet-sdk-9.0 aspnetcore-runtime-9.0
EOF



#5 Create locally a new MVC project

dotnet new mvc --force


#6 Modify Index.cshtml to update welcome message
INDEX_FILE="Views/Home/Index.cshtml"

if [ -f "$INDEX_FILE" ]; then
  sed -i 's/<h1 class="display-4">Welcome<\/h1>/<h1 class="display-4">Welcome to Muhammad's MVC WebApp<\/h1>/g' "$INDEX_FILE"
  echo "Updated Index.cshtml with custom welcome message."
else
  echo "Error: $INDEX_FILE not found!"
fi


#7️ Publish the .NET application
dotnet publish -c Release

#8️ Copy the published app to Azure VM
scp -r bin/Release/net*/publish/* azureuser@$PUBLIC_IP:~/webapp/
echo "Copying files to Azure VM"


#9️ Create & Register a systemd Service
ssh azureuser@$PUBLIC_IP << 'ENDSSH'
    sudo tee /etc/systemd/system/myapp.service > /dev/null <<EOF
   [Unit]
Description=ASP.NET Web App running on Ubuntu
After=network.target

[Service]
WorkingDirectory=/home/azureuser/webapp
ExecStart=/usr/bin/dotnet /home/azureuser/webapp/webapp.dll --urls http://0.0.0.0:5000
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=myapp
User=azureuser
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_ROOT=/usr/share/dotnet
Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

[Install]
WantedBy=multi-user.target
    EOF
ENDSSH

#10  Activate the Service
ssh azureuser@$PUBLIC_IP << 'ENDSSH'
    sudo systemctl daemon-reload
    sudo systemctl enable myapp.service
    sudo systemctl start myapp.service
    echo "Systemd Service Started"
ENDSSH

#11 Test the Application
ssh azureuser@$PUBLIC_IP "sudo systemctl status myapp.service"

echo "App Running on http://$PUBLIC_IP:5000"
echo "App Deployed & Ready for Testing"





