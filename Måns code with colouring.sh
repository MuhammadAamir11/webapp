#!/bin/bash

# Färgkoder för bättre läsbarhet
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
# =========================================================
# Konfigureringsvariabler, ändra här för att ändra VM-Setup
RESOURCE_GROUP="MVCAppRG"    # Exempel: "MVCAppRG"
VM_NAME="MVCAppVM"           # Exempel "MVCAppVM"
LOCATION="northeurope"        # Exempel: "northeurope"
APP_NAME="DemoApp"            # Exempel: "DemoApp"
USERNAME="azureuser"          # Exempel: "azureuser"
IMAGE="Ubuntu2204"            # Exempel: "Ubuntu2204"
SIZE="Standard_B1s"           # Exempel: "Standard_B1s"
LM_DIRECTORY="~/Developer/Azure" # Exempel: "~/Developer/dir-Du-vill-spara-i"
VM_DIRECTORY="~/webapp"
# =========================================================

echo -e "${GREEN}=== Startar deployment process ===${NC}"

# Funktion för att kontrollera om ett kommando lyckades
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$1 lyckades${NC}"
    else
        echo -e "${RED}$1 misslyckades${NC}"
        exit 1
    fi
}

# 1. Skapa resursgrupp
echo -e "${YELLOW}Skapar resursgrupp...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION
check_status "Skapa resursgrupp"

# 2. Skapa VM
echo -e "${YELLOW}Skapar virtuell maskin...${NC}"
VM_INFO=$(az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --image $IMAGE \
    --admin-username $USERNAME \
    --generate-ssh-keys \
    --size $SIZE)
check_status "Skapa VM"

# Hämta public IP
PUBLIC_IP=$(echo $VM_INFO | jq -r .publicIpAddress) # Sparar Public IP i PUBLIC_IP
echo -e "${GREEN}VM skapad med IP: $PUBLIC_IP${NC}"

# 3. Öppna port 5000
echo -e "${YELLOW}Öppnar port 5000...${NC}"
az vm open-port --resource-group $RESOURCE_GROUP --name $VM_NAME --port 5000 --priority 890
check_status "Öppna port"

# 4. Skapa lokal MVC-app
echo -e "${YELLOW}Skapar MVC-app lokalt...${NC}"
mkdir -p $DIRECTORY
cd $LM_DIRECTORY
dotnet new mvc -n $APP_NAME
cd $APP_NAME
check_status "Skapa MVC-app"

# 5. Publicera appen
echo -e "${YELLOW}Publicerar appen...${NC}"
dotnet publish -c Release
check_status "Publicera app"

# 6. Vänta på att VM ska vara redo
echo -e "${YELLOW}Väntar på att VM ska vara redo...${NC}"
sleep 30

# 7. Konfigurera VM
echo -e "${YELLOW}Konfigurerar VM...${NC}"
ssh -o StrictHostKeyChecking=no $USERNAME@$PUBLIC_IP << 'ENDSSH'
    # Skapa webapp-mapp
    mkdir -p $VM_DIRECTORY

    # Installera .NET
    wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    
    sudo apt-get update
    sudo apt-get install -y aspnetcore-runtime-8.0 # Startar inte appen är det troligen denna som är fel, Testa 9 eller 8
    sudo apt-get install -y dotnet-sdk-9.0

    # Skapa systemd service fil
    sudo tee /etc/systemd/system/demoapp.service << 'EOF'
[Unit]
Description=DemoApp MVC Web Application
After=network.target

[Service]
WorkingDirectory=/home/azureuser/webapp
ExecStart=/usr/bin/dotnet /home/azureuser/webapp/DemoApp.dll
Restart=always
User=azureuser
Group=azureuser
Environment=DOTNET_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000

[Install]
WantedBy=multi-user.target
EOF

    # Aktivera och starta servicen
    sudo systemctl enable demoapp.service
    sudo systemctl start demoapp.service
ENDSSH
check_status "Konfigurera VM"

# 8. Kopiera filer till VM
echo -e "${YELLOW}Kopierar filer till VM...${NC}"
scp -r bin/Release/net*/publish/* $USERNAME@$PUBLIC_IP:$VM_DIRECTORY
check_status "Kopiera filer"

# 9. Starta om servicen
echo -e "${YELLOW}Startar om servicen...${NC}"
ssh $USERNAME@$PUBLIC_IP "sudo systemctl restart demoapp.service"
check_status "Starta om service"

echo -e "${GREEN}=== Deployment slutförd ===${NC}"
echo -e "${GREEN}Appen är tillgänglig på: http://$PUBLIC_IP:5000${NC}"