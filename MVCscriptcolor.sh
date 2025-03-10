#!/bin/bash

# 🎨 Define color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ✅ Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$1 succeeded ✅${NC}"
    else
        echo -e "${RED}$1 failed ❌${NC}"
        exit 1
    fi
}

# 1️⃣ Create resource group
echo -e "${YELLOW}Creating resource group...${NC}"
az group create --name MVCAppRG --location northeurope
check_status "Resource group creation"

# 2️⃣ Create Azure VM
echo -e "${YELLOW}Creating virtual machine...${NC}"
az vm create \
  --resource-group MVCAppRG \
  --name MVCAppVM \
  --image Ubuntu2204 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --size Standard_B1s
check_status "VM creation"

# 3️⃣ Fetch Public IP Address & Open Port 5000
echo -e "${YELLOW}Fetching Public IP and opening port 5000...${NC}"
PUBLIC_IP=$(az vm show -d -g MVCAppRG -n MVCAppVM --query publicIps -o tsv)
echo -e "${GREEN}VM Public IP: $PUBLIC_IP${NC}"
az vm open-port --resource-group MVCAppRG --name MVCAppVM --port 5000 --priority 890
check_status "Port 5000 opened"

# 4️⃣ Install .NET SDK & Runtime on Azure VM
echo -e "${YELLOW}Installing .NET SDK & Runtime on Azure VM...${NC}"
ssh -o StrictHostKeyChecking=no azureuser@$PUBLIC_IP << 'EOF'
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    sudo apt-get update -y
    sudo apt-get install -y dotnet-sdk-9.0 aspnetcore-runtime-9.0
EOF
check_status ".NET SDK & Runtime installed"

# 5️⃣ Create a new MVC project
echo -e "${YELLOW}Creating new MVC project...${NC}"
dotnet new mvc --force
check_status "MVC project created"

# 6️⃣ Modify Index.cshtml to update welcome message
INDEX_FILE="Views/Home/Index.cshtml"
echo -e "${YELLOW}Updating welcome message...${NC}"
if [ -f "$INDEX_FILE" ]; then
  sed -i 's/<h1 class="display-4">Welcome<\/h1>/<h1 class="display-4">Welcome to Muhammads MVC WebApp<\/h1>/g' "$INDEX_FILE"
  check_status "Welcome message updated"
else
  echo -e "${RED}Error: $INDEX_FILE not found!${NC}"
  exit 1
fi

# 7️⃣ Publish the .NET application
echo -e "${YELLOW}Publishing the .NET application...${NC}"
dotnet publish -c Release
check_status "Application published"

# 8️⃣ Copy the published app to Azure VM
echo -e "${YELLOW}Copying application files to Azure VM...${NC}"
scp -r bin/Release/net*/publish/* azureuser@$PUBLIC_IP:~/webapp/
check_status "Files copied to Azure VM"

# 9️⃣ Create & Register a systemd Service
echo -e "${YELLOW}Creating systemd service file...${NC}"
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
    Environment="ASPNETCORE_ENVIRONMENT=Production"
    Environment="DOTNET_ROOT=/usr/share/dotnet"
    Environment="DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1"

    [Install]
    WantedBy=multi-user.target
    EOF
ENDSSH
check_status "Systemd service file created"

# 🔟 Activate the Service
echo -e "${YELLOW}Activating the systemd service...${NC}"
ssh azureuser@$PUBLIC_IP << 'ENDSSH'
    sudo systemctl daemon-reload
    sudo systemctl enable myapp.service

    # Check if service is running
    if sudo systemctl is-active --quiet myapp.service; then
        echo "Service is already running. Restarting it..."
        sudo systemctl restart myapp.service
    else
        echo "Starting the service..."
        sudo systemctl start myapp.service
    fi

    # Check if port 5000 is occupied
    if sudo ss -tulnp | grep -q ':5000'; then
        echo "Port 5000 is still in use. Restarting service..."
        sudo fuser -k 5000/tcp
        sudo systemctl restart myapp.service
    fi

    echo "Systemd Service Started"
ENDSSH
check_status "Service activated"

# ✅ Test the Application
echo -e "${YELLOW}Checking service status...${NC}"
ssh azureuser@$PUBLIC_IP "sudo systemctl status myapp.service"

echo -e "${GREEN}App Running on http://$PUBLIC_IP:5000${NC}"
echo -e "${GREEN}App Deployed & Ready for Testing 🎉${NC}"
