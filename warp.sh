#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Function to wait for port to be available
wait_for_port() {
    local port=$1
    local max_attempts=$2
    local attempt=1
    
    echo "Waiting for port $port to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        if ss -tlnp | grep -q ":$port "; then
            echo -e "${GREEN}✓${NC} Port $port is now listening (attempt $attempt/$max_attempts)"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Port $port not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}✗${NC} Port $port is not available after $max_attempts attempts"
    return 1
}

# Function to wait for service to be fully ready
wait_for_service() {
    local service_name=$1
    local max_attempts=$2
    local attempt=1
    
    echo "Waiting for $service_name to be fully ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service_name"; then
            echo -e "${GREEN}✓${NC} Service $service_name is active (attempt $attempt/$max_attempts)"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Service $service_name not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}✗${NC} Service $service_name is not ready after $max_attempts attempts"
    return 1
}

# Function to test WARP connection
test_warp_connection() {
    local max_attempts=5
    local attempt=1
    
    echo "Testing WARP connection..."
    echo
    
    while [ $attempt -le $max_attempts ]; do
        echo "Connection test attempt $attempt/$max_attempts..."
        
        # Test with timeout
        if timeout 15 curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 --silent \
           https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "warp="; then
            echo -e "${GREEN}✓${NC} WARP connection test successful!"
            return 0
        fi
        
        echo "Connection test failed, waiting before retry..."
        sleep 3
        ((attempt++))
    done
    
    echo -e "${YELLOW}⚠${NC} WARP connection test failed after $max_attempts attempts"
    echo "This might be normal during initial setup. You can test later with: warp test"
    return 1
}

# Function to show service logs if there's an issue
show_service_logs() {
    echo
    echo -e "${YELLOW}Service logs (last 20 lines):${NC}"
    journalctl -u wireproxy.service -n 20 --no-pager
}

# WireProxy WARP Management Script
echo
echo -e "${PURPLE}===============${NC}"
echo -e "${NC}WIREPROXY WARP${NC}"
echo -e "${PURPLE}===============${NC}"
echo

# Check if script is run with parameters
if [ "$1" = "uninstall" ] || [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
   ACTION="uninstall"
elif [ "$1" = "install" ] || [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
   ACTION="install"
else
   # Interactive menu
   echo -e "${CYAN}Please select an action:${NC}"
   echo
   echo -e "${GREEN}1.${NC} Install"
   echo -e "${YELLOW}2.${NC} Uninstall"
   echo -e "${RED}3.${NC} Exit"
   echo
   
   while true; do
       echo -ne "${CYAN}Enter your choice (1-3): ${NC}"
       read CHOICE
       case $CHOICE in
           1)
               ACTION="install"
               break
               ;;
           2)
               ACTION="uninstall"
               break
               ;;
           3)
               echo -e "${CYAN}Goodbye!${NC}"
               exit 0
               ;;
           *)
               echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
               ;;
       esac
   done
fi

# Uninstall function
if [ "$ACTION" = "uninstall" ]; then
   echo
   echo -e "${PURPLE}===========================${NC}"
   echo -e "${NC}WireProxy WARP Uninstaller${NC}"
   echo -e "${PURPLE}===========================${NC}"
   echo

   # Check if WireProxy is installed
   if [ ! -f "/usr/bin/wireproxy" ] && [ ! -f "/etc/systemd/system/wireproxy.service" ]; then
       echo -e "${YELLOW}WireProxy WARP is not installed on this system.${NC}"
       exit 0
   fi

   # Confirmation
   echo -ne "${YELLOW}Are you sure you want to continue? (y/N): ${NC}"
   read -r CONFIRM

   if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
       echo -e "${CYAN}Uninstallation cancelled.${NC}"
       exit 0
   fi

   echo
   echo -e "${GREEN}========================${NC}"
   echo -e "${NC}Removing WireProxy WARP${NC}"
   echo -e "${GREEN}========================${NC}"
   echo

   # Stop and disable service
   echo "Stopping WireProxy service..."
   systemctl stop wireproxy 2>/dev/null && echo -e "${GREEN}✓${NC} Service stopped" || echo "ℹ Service was not running"
   systemctl disable wireproxy 2>/dev/null && echo -e "${GREEN}✓${NC} Service disabled" || echo "ℹ Service was not enabled"

   # Remove systemd service
   echo
   echo "Removing systemd service..."
   if [ -f "/etc/systemd/system/wireproxy.service" ]; then
       rm -f /etc/systemd/system/wireproxy.service
       systemctl daemon-reload
       echo -e "${GREEN}✓${NC} Systemd service removed"
   else
       echo "ℹ Systemd service file not found"
   fi

   # Remove configuration files
   echo
   echo "Removing configuration files..."
   if [ -f "/etc/wireguard/proxy.conf" ]; then
       rm -f /etc/wireguard/proxy.conf
       echo -e "${GREEN}✓${NC} Configuration file removed"
   else
       echo "ℹ Configuration file not found"
   fi
   
   # Remove directory if empty
   if [ -d "/etc/wireguard" ] && [ -z "$(ls -A /etc/wireguard)" ]; then
       rmdir /etc/wireguard
       echo -e "${GREEN}✓${NC} Empty wireguard directory removed"
   fi

   # Remove WireProxy binary
   echo
   echo "Removing WireProxy binary..."
   if [ -f "/usr/bin/wireproxy" ]; then
       rm -f /usr/bin/wireproxy
       echo -e "${GREEN}✓${NC} WireProxy binary removed"
   else
       echo "ℹ WireProxy binary not found"
   fi

   # Remove management script
   echo
   echo "Removing management script..."
   if [ -f "/usr/bin/warp" ]; then
       rm -f /usr/bin/warp
       echo -e "${GREEN}✓${NC} Management script removed"
   else
       echo "ℹ Management script not found"
   fi

   # Remove temporary files
   echo
   echo "Cleaning up temporary files..."
   rm -f /tmp/warp-account.conf /tmp/wireproxy.tar.gz
   echo -e "${GREEN}✓${NC} Temporary files cleaned"

   echo
   echo -e "${GREEN}===========================================${NC}"
   echo -e "${GREEN}✓${NC} WireProxy WARP uninstalled successfully!"
   echo -e "${GREEN}===========================================${NC}"
   echo
   exit 0
fi

# Installation process
echo
echo -e "${PURPLE}=====================${NC}"
echo -e "${NC}WireProxy WARP Setup${NC}"
echo -e "${PURPLE}=====================${NC}"
echo

# Check if already installed
if [ -f "/usr/bin/wireproxy" ] && [ -f "/etc/systemd/system/wireproxy.service" ]; then
   echo -e "${YELLOW}WireProxy WARP appears to be already installed.${NC}"
   echo -ne "${YELLOW}Do you want to reinstall? (y/N): ${NC}"
   read -r REINSTALL
   
   if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
       echo -e "${CYAN}Installation cancelled.${NC}"
       echo -e "${CYAN}Use 'warp status' to check current installation.${NC}"
       exit 0
   fi
   
   echo -e "${YELLOW}Proceeding with reinstallation...${NC}"
fi

set -e

echo -e "${GREEN}======================${NC}"
echo -e "${NC}1. System preparation${NC}"
echo -e "${GREEN}======================${NC}"
echo

# Update package list and install basic packages
echo "Updating package list and installing dependencies..."
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget net-tools iproute2 iptables jq tar >/dev/null 2>&1

echo
echo -e "${GREEN}--------------------------------${NC}"
echo -e "${GREEN}✓${NC} System preparation completed!"
echo -e "${GREEN}--------------------------------${NC}"
echo

echo -e "${GREEN}=========================${NC}"
echo -e "${NC}2. Creating WARP account${NC}"
echo -e "${GREEN}=========================${NC}"
echo

# Create directory structure
echo "Creating directory structure..."
echo
mkdir -p /etc/wireguard

# Register WARP account
echo "Registering WARP account..."
curl -s "https://warp.cloudflare.now.cc/?run=register" > /tmp/warp-account.conf 2>/dev/null

# Verify account creation
if [ ! -s /tmp/warp-account.conf ]; then
   echo -e "${RED}Failed to create WARP account!${NC}"
   exit 1
fi

echo "WARP account registered successfully!"

echo
echo -e "${GREEN}-----------------------------------${NC}"
echo -e "${GREEN}✓${NC} WARP account creation completed!"
echo -e "${GREEN}-----------------------------------${NC}"
echo

echo -e "${GREEN}========================${NC}"
echo -e "${NC}3. Installing WireProxy${NC}"
echo -e "${GREEN}========================${NC}"
echo

# Determine architecture
echo "Detecting system architecture..."
ARCH=$(uname -m)
case $ARCH in
   x86_64) ARCH="amd64" ;;
   aarch64) ARCH="arm64" ;;
   *) 
       echo -e "${RED}Unsupported architecture: $ARCH${NC}"
       exit 1
       ;;
esac
echo "Architecture detected: $ARCH"

# Download and install WireProxy
echo
echo "Downloading WireProxy..."
wget -O /tmp/wireproxy.tar.gz "https://github.com/pufferffish/wireproxy/releases/download/v1.0.9/wireproxy_linux_${ARCH}.tar.gz" >/dev/null 2>&1

if [ ! -f /tmp/wireproxy.tar.gz ]; then
   echo -e "${RED}Failed to download WireProxy!${NC}"
   exit 1
fi

echo
echo "Installing WireProxy..."
tar xzf /tmp/wireproxy.tar.gz -C /usr/bin/ >/dev/null 2>&1
chmod +x /usr/bin/wireproxy >/dev/null 2>&1

# Clean up
rm -f /tmp/wireproxy.tar.gz >/dev/null 2>&1

echo
echo -e "${GREEN}------------------------------------${NC}"
echo -e "${GREEN}✓${NC} WireProxy installation completed!"
echo -e "${GREEN}------------------------------------${NC}"
echo

echo -e "${GREEN}==========================${NC}"
echo -e "${NC}4. Creating configuration${NC}"
echo -e "${GREEN}==========================${NC}"
echo

# Extract data from WARP account
echo "Extracting WARP account data..."
PRIVATE_KEY=$(jq -r '.private_key' /tmp/warp-account.conf)
ADDRESS_V6=$(jq -r '.config.interface.addresses.v6' /tmp/warp-account.conf)

if [ "$PRIVATE_KEY" == "null" ] || [ "$ADDRESS_V6" == "null" ]; then
   echo -e "${RED}Failed to extract account data!${NC}"
   exit 1
fi

echo "Private Key: ${PRIVATE_KEY:0:20}..."
echo "IPv6 Address: $ADDRESS_V6"

# Create WireProxy configuration
echo
echo "Creating WireProxy configuration..."
cat > /etc/wireguard/proxy.conf << EOF
[Interface]
Address = 172.16.0.2/32
Address = ${ADDRESS_V6}/128
MTU = 1280
PrivateKey = ${PRIVATE_KEY}
DNS = 1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
Endpoint = engage.cloudflareclient.com:2408
AllowedIPs = 0.0.0.0/0, ::/0

[Socks5]
BindAddress = 127.0.0.1:40000
EOF

echo
echo -e "${GREEN}------------------------------------${NC}"
echo -e "${GREEN}✓${NC} Configuration creation completed!"
echo -e "${GREEN}------------------------------------${NC}"
echo

echo -e "${GREEN}=========================${NC}"
echo -e "${NC}5. Testing configuration${NC}"
echo -e "${GREEN}=========================${NC}"
echo

# Test configuration
echo "Testing WireProxy configuration..."
timeout 10 /usr/bin/wireproxy -c /etc/wireguard/proxy.conf >/dev/null 2>&1 &
WIREPROXY_PID=$!

sleep 3

if kill -0 $WIREPROXY_PID 2>/dev/null; then
   echo -e "${GREEN}Configuration test passed!${NC}"
   kill $WIREPROXY_PID 2>/dev/null || true
   sleep 1
else
   echo -e "${RED}Configuration test failed!${NC}"
   exit 1
fi

echo
echo -e "${GREEN}-----------------------------------${NC}"
echo -e "${GREEN}✓${NC} Configuration testing completed!"
echo -e "${GREEN}-----------------------------------${NC}"
echo

echo -e "${GREEN}============================${NC}"
echo -e "${NC}6. Creating systemd service${NC}"
echo -e "${GREEN}============================${NC}"
echo

# Create systemd service
echo "Creating systemd service..."
echo
cat > /etc/systemd/system/wireproxy.service << EOF
[Unit]
Description=WireProxy for WARP
After=network.target
Documentation=https://github.com/pufferffish/wireproxy

[Service]
ExecStart=/usr/bin/wireproxy -c /etc/wireguard/proxy.conf
RemainAfterExit=yes
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
echo "Starting WireProxy service..."
systemctl daemon-reload >/dev/null 2>&1
systemctl start wireproxy >/dev/null 2>&1
systemctl enable wireproxy >/dev/null 2>&1

echo
echo -e "${GREEN}--------------------------------------${NC}"
echo -e "${GREEN}✓${NC} Systemd service creation completed!"
echo -e "${GREEN}--------------------------------------${NC}"
echo

echo -e "${GREEN}==============================${NC}"
echo -e "${NC}7. Creating management script${NC}"
echo -e "${GREEN}==============================${NC}"
echo

# Create management script
echo "Creating management script..."
cat > /usr/bin/warp << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

case "$1" in
   start)
       systemctl start wireproxy
       echo -e "${GREEN}WireProxy started${NC}"
       ;;
   stop)
       systemctl stop wireproxy
       echo -e "${YELLOW}WireProxy stopped${NC}"
       ;;
   restart)
       systemctl restart wireproxy
       echo -e "${GREEN}WireProxy restarted${NC}"
       ;;
   status)
       systemctl status wireproxy
       ;;
   test)
       echo -e "${YELLOW}Testing WARP connection...${NC}"
       if timeout 15 curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "warp="; then
           echo -e "${GREEN}WARP connection is working!${NC}"
           echo "Your IP information:"
           timeout 15 curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 --silent https://ipinfo.io 2>/dev/null || echo -e "${YELLOW}Could not fetch IP info${NC}"
       else
           echo -e "${RED}WARP connection failed!${NC}"
           echo "Check service status: systemctl status wireproxy"
       fi
       ;;
   info)
       echo -e "${GREEN}WireProxy WARP Information:${NC}"
       echo "SOCKS5 Proxy: 127.0.0.1:40000"
       echo "Service status:"
       systemctl is-active wireproxy
       echo "Port status:"
       ss -tlnp | grep 40000 || echo "Port not listening"
       ;;
   logs)
       journalctl -u wireproxy.service -f
       ;;
   uninstall)
       echo
       echo -e "${PURPLE}WireProxy WARP Uninstaller${NC}"
       echo
       echo -e "${YELLOW}This will completely remove WireProxy WARP setup.${NC}"
       echo
       echo -ne "${YELLOW}Are you sure you want to continue? (y/N): ${NC}"
       read -r CONFIRM

       if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
           echo -e "${CYAN}Uninstallation cancelled.${NC}"
           exit 0
       fi

       echo
       echo "Stopping WireProxy service..."
       systemctl stop wireproxy 2>/dev/null
       systemctl disable wireproxy 2>/dev/null

       echo "Removing systemd service..."
       rm -f /etc/systemd/system/wireproxy.service
       systemctl daemon-reload

       echo "Removing configuration files..."
       rm -f /etc/wireguard/proxy.conf
       rmdir /etc/wireguard 2>/dev/null || true

       echo "Removing WireProxy binary..."
       rm -f /usr/bin/wireproxy

       echo "Removing management script..."
       rm -f /usr/bin/warp

       echo "Cleaning up temporary files..."
       rm -f /tmp/warp-account.conf /tmp/wireproxy.tar.gz

       echo
       echo -e "${GREEN}WireProxy WARP uninstalled successfully!${NC}"
       ;;
   *)
       echo "WireProxy WARP Management Script"
       echo ""
       echo "Usage: $0 {start|stop|restart|status|test|info|logs|uninstall}"
       echo ""
       echo "Commands:"
       echo "  start      - Start WireProxy service"
       echo "  stop       - Stop WireProxy service"  
       echo "  restart    - Restart WireProxy service"
       echo "  status     - Show service status"
       echo "  test       - Test WARP connection"
       echo "  info       - Show proxy information"
       echo "  logs       - Show real-time logs"
       echo -e "  ${RED}uninstall  - Completely remove WireProxy WARP${NC}"
       echo ""
       echo "Examples:"
       echo "  curl --proxy socks5h://127.0.0.1:40000 https://ipinfo.io"
       echo "  curl --proxy socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace"
       exit 1
       ;;
esac
EOF

chmod +x /usr/bin/warp >/dev/null 2>&1

echo
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${GREEN}✓${NC} Management script creation completed!"
echo -e "${GREEN}----------------------------------------${NC}"
echo

echo -e "${GREEN}======================${NC}"
echo -e "${NC}8. Final verification${NC}"
echo -e "${GREEN}======================${NC}"
echo

# Final verification with proper waiting
echo "Performing final verification..."
echo

# Wait for service to be ready
if ! wait_for_service "wireproxy" 15; then
    echo -e "${RED}Service verification failed!${NC}"
    show_service_logs
    exit 1
fi

# Wait for port to be available
if ! wait_for_port "40000" 15; then
    echo -e "${RED}Port verification failed!${NC}"
    show_service_logs
    exit 1
fi

# Test WARP connection
echo
test_warp_connection

# Clean up temporary files
rm -f /tmp/warp-account.conf >/dev/null 2>&1

echo
echo -e "${GREEN}--------------------------------${NC}"
echo -e "${GREEN}✓${NC} Final verification completed!"
echo -e "${GREEN}--------------------------------${NC}"
echo

echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}✓${NC} WireProxy WARP setup completed successfully!"
echo -e "${GREEN}===============================================${NC}"
echo
echo -e "${CYAN}SOCKS5 Proxy Information:${NC}"
echo -e "Address: ${WHITE}127.0.0.1:40000${NC}"
echo
echo -e "${CYAN}Management Commands:${NC}"
echo -e "Check status: ${WHITE}warp status${NC}"
echo -e "Test connection: ${WHITE}warp test${NC}"
echo -e "Show information: ${WHITE}warp info${NC}"
echo -e "View logs: ${WHITE}warp logs${NC}"
echo -e "Uninstall: ${RED}warp uninstall${NC}"
echo
echo -e "${CYAN}Test with curl:${NC}" 
echo -e "${NC}curl --proxy socks5h://127.0.0.1:40000 https://ipinfo.io${NC}"
echo
echo -e "${CYAN}Check WARP status:${NC}" 
echo -e "${NC}curl --proxy socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace${NC}"
echo
