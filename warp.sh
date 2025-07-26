#!/bin/bash

#========================
# WIREPROXY WARP MANAGER
#========================

# Color constants
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Status symbols
readonly CHECK="✓"
readonly CROSS="✗"
readonly WARNING="!"
readonly INFO="*"
readonly ARROW="→"

#======================
# VALIDATION FUNCTIONS
#======================

# Wait for port to be available
wait_for_port() {
    local port=$1
    local max_attempts=$2
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ss -tlnp | grep -q ":$port "; then
            return 0
        fi
        
        sleep 2
        ((attempt++))
    done
    
    return 1
}

# Wait for service to be fully ready
wait_for_service() {
    local service_name=$1
    local max_attempts=$2
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service_name"; then
            return 0
        fi
        
        sleep 2
        ((attempt++))
    done
    
    return 1
}

#===========================
# CONNECTION TEST FUNCTIONS
#===========================

# Test WARP connection
test_warp_connection() {
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Test with timeout
        if timeout 15 curl --proxy socks5h://127.0.0.1:40000 --connect-timeout 10 --silent \
           https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "warp="; then
            return 0
        fi
        
        sleep 3
        ((attempt++))
    done
    
    echo -e "${YELLOW}${WARNING}${NC} WARP connection test failed after $max_attempts attempts"
    echo -e "${YELLOW}This might be normal during initial setup. You can test later with: warp test${NC}"
    return 1
}

#===================
# LOGGING FUNCTIONS
#===================

# Show service logs if there's an issue
show_service_logs() {
    echo
    echo -e "${YELLOW}Service logs (last 20 lines):${NC}"
    journalctl -u wireproxy.service -n 20 --no-pager
}

#====================
# UNINSTALL FUNCTION
#====================

perform_uninstall() {
    echo
    echo -e "${PURPLE}===========================${NC}"
    echo -e "${WHITE}WireProxy WARP Uninstaller${NC}"
    echo -e "${PURPLE}===========================${NC}"
    echo

    # Check if WireProxy is installed
    if [ ! -f "/usr/bin/wireproxy" ] && [ ! -f "/etc/systemd/system/wireproxy.service" ]; then
        echo -e "${YELLOW}${WARNING}${NC} WireProxy WARP is not installed on this system."
        echo
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
    echo -e "${GREEN}Service Management${NC}"
    echo -e "${GREEN}==================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Stopping WireProxy service..."
    echo -e "${GRAY}  ${ARROW}${NC} Stopping service"
    systemctl stop wireproxy 2>/dev/null && echo -e "${GRAY}  ${ARROW}${NC} Service stopped" || echo -e "${GRAY}  ${ARROW}${NC} Service was not running"
    echo -e "${GRAY}  ${ARROW}${NC} Disabling service"
    systemctl disable wireproxy 2>/dev/null && echo -e "${GRAY}  ${ARROW}${NC} Service disabled" || echo -e "${GRAY}  ${ARROW}${NC} Service was not enabled"
    echo -e "${GREEN}${CHECK}${NC} Service management completed!"
    echo

    echo -e "${GREEN}System Cleanup${NC}"
    echo -e "${GREEN}==============${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Removing systemd service..."
    if [ -f "/etc/systemd/system/wireproxy.service" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Removing service file"
        rm -f /etc/systemd/system/wireproxy.service
        echo -e "${GRAY}  ${ARROW}${NC} Reloading systemd daemon"
        systemctl daemon-reload
        echo -e "${GREEN}${CHECK}${NC} Systemd service removed"
    else
        echo -e "${GREEN}${CHECK}${NC} Systemd service file not found"
    fi

    echo

    echo -e "${CYAN}${INFO}${NC} Removing configuration files..."
    if [ -f "/etc/wireguard/proxy.conf" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Removing configuration file"
        rm -f /etc/wireguard/proxy.conf
        echo -e "${GREEN}${CHECK}${NC} Configuration file removed"
    else
        echo -e "${GREEN}${CHECK}${NC} Configuration file not found"
    fi
    
    # Remove directory if empty
    if [ -d "/etc/wireguard" ] && [ -z "$(ls -A /etc/wireguard)" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Removing empty wireguard directory"
        rmdir /etc/wireguard
        echo -e "${GREEN}${CHECK}${NC} Empty wireguard directory removed"
    fi

    echo

    echo -e "${CYAN}${INFO}${NC} Removing WireProxy binary..."
    if [ -f "/usr/bin/wireproxy" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Removing binary file"
        rm -f /usr/bin/wireproxy
        echo -e "${GREEN}${CHECK}${NC} WireProxy binary removed"
    else
        echo -e "${GREEN}${CHECK}${NC} WireProxy binary not found"
    fi

    echo

    echo -e "${CYAN}${INFO}${NC} Removing management script..."
    if [ -f "/usr/bin/warp" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Removing management script"
        rm -f /usr/bin/warp
        echo -e "${GREEN}${CHECK}${NC} Management script removed"
    else
        echo -e "${GREEN}${CHECK}${NC} Management script not found"
    fi

    echo

    echo -e "${CYAN}${INFO}${NC} Cleaning up temporary files..."
    echo -e "${GRAY}  ${ARROW}${NC} Removing temporary files"
    rm -f /tmp/warp-account.conf /tmp/wireproxy.tar.gz
    echo -e "${GREEN}${CHECK}${NC} Temporary files cleaned"
    echo

    echo -e "${PURPLE}=====================${NC}"
    echo -e "${GREEN}${CHECK}${NC} Removal complete!"
    echo -e "${PURPLE}=====================${NC}"
    echo
    exit 0
}

#========================
# INSTALLATION FUNCTIONS
#========================

prepare_system() {
    echo -e "${GREEN}System Preparation${NC}"
    echo -e "${GREEN}==================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Updating package list and installing dependencies..."
    echo -e "${GRAY}  ${ARROW}${NC} Updating package repositories"
    apt-get update -y >/dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Installing required packages"
    apt-get install -y curl wget net-tools iproute2 iptables jq tar >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Dependencies installed successfully!"
    echo
}

setup_warp_account() {
    echo -e "${GREEN}WARP Account Setup${NC}"
    echo -e "${GREEN}==================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Setting up directory structure..."
    echo -e "${GRAY}  ${ARROW}${NC} Creating /etc/wireguard directory"
    mkdir -p /etc/wireguard
    echo -e "${GREEN}${CHECK}${NC} Directory structure created!"

    echo

    echo -e "${CYAN}${INFO}${NC} Registering WARP account..."
    echo -e "${GRAY}  ${ARROW}${NC} Contacting Cloudflare WARP API"
    curl -s "https://warp.cloudflare.now.cc/?run=register" > /tmp/warp-account.conf 2>/dev/null

    # Verify account creation
    if [ ! -s /tmp/warp-account.conf ]; then
        echo -e "${RED}${CROSS}${NC} Failed to create WARP account!"
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Account registration successful"
    echo -e "${GREEN}${CHECK}${NC} WARP account registered successfully!"
    echo
}

install_wireproxy() {
    echo -e "${GREEN}WireProxy Installation${NC}"
    echo -e "${GREEN}======================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Detecting system architecture..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) 
            echo -e "${RED}${CROSS}${NC} Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    echo -e "${GRAY}  ${ARROW}${NC} Architecture detected: $ARCH"
    echo -e "${GREEN}${CHECK}${NC} Architecture detection completed!"

    echo

    echo -e "${CYAN}${INFO}${NC} Downloading and installing WireProxy..."
    echo -e "${GRAY}  ${ARROW}${NC} Downloading WireProxy binary"
    wget -O /tmp/wireproxy.tar.gz "https://github.com/pufferffish/wireproxy/releases/download/v1.0.9/wireproxy_linux_${ARCH}.tar.gz" >/dev/null 2>&1

    if [ ! -f /tmp/wireproxy.tar.gz ]; then
        echo -e "${RED}${CROSS}${NC} Failed to download WireProxy!"
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Extracting and installing binary"
    tar xzf /tmp/wireproxy.tar.gz -C /usr/bin/ >/dev/null 2>&1
    chmod +x /usr/bin/wireproxy >/dev/null 2>&1

    echo -e "${GRAY}  ${ARROW}${NC} Cleaning up temporary files"
    rm -f /tmp/wireproxy.tar.gz >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} WireProxy installation completed!"
    echo
}

create_configuration() {
    echo -e "${GREEN}Configuration Creation${NC}"
    echo -e "${GREEN}======================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Extracting WARP account data..."
    echo -e "${GRAY}  ${ARROW}${NC} Reading account configuration"
    PRIVATE_KEY=$(jq -r '.private_key' /tmp/warp-account.conf)
    ADDRESS_V6=$(jq -r '.config.interface.addresses.v6' /tmp/warp-account.conf)

    if [ "$PRIVATE_KEY" == "null" ] || [ "$ADDRESS_V6" == "null" ]; then
        echo -e "${RED}${CROSS}${NC} Failed to extract account data!"
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Private Key: ${PRIVATE_KEY:0:20}..."
    echo -e "${GRAY}  ${ARROW}${NC} IPv6 Address: $ADDRESS_V6"
    echo -e "${GREEN}${CHECK}${NC} Account data extracted successfully!"

    echo

    echo -e "${CYAN}${INFO}${NC} Creating WireProxy configuration..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing configuration file"
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

    echo -e "${GREEN}${CHECK}${NC} Configuration file created successfully!"
    echo
}

test_configuration() {
    echo -e "${GREEN}Configuration Testing${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Testing WireProxy configuration..."
    echo -e "${GRAY}  ${ARROW}${NC} Starting test instance"
    timeout 10 /usr/bin/wireproxy -c /etc/wireguard/proxy.conf >/dev/null 2>&1 &
    WIREPROXY_PID=$!

    echo -e "${GRAY}  ${ARROW}${NC} Waiting for test completion"
    sleep 3

    if kill -0 $WIREPROXY_PID 2>/dev/null; then
        echo -e "${GRAY}  ${ARROW}${NC} Stopping test instance"
        kill $WIREPROXY_PID 2>/dev/null || true
        sleep 1
        echo -e "${GREEN}${CHECK}${NC} Configuration test passed!"
    else
        echo -e "${RED}${CROSS}${NC} Configuration test failed!"
        exit 1
    fi

    echo
}

setup_systemd_service() {
    echo -e "${GREEN}Systemd Service Setup${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Creating systemd service..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing service configuration"
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

    echo -e "${GRAY}  ${ARROW}${NC} Reloading systemd daemon"
    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Starting WireProxy service"
    systemctl start wireproxy >/dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Enabling service for auto-start"
    systemctl enable wireproxy >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Systemd service setup completed!"
    echo
}

create_management_script() {
    echo -e "${GREEN}Management Script Creation${NC}"
    echo -e "${GREEN}==========================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Creating management script..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing management script"
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
        echo
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

    echo -e "${GRAY}  ${ARROW}${NC} Setting script permissions"
    chmod +x /usr/bin/warp >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Management script created successfully!"
    echo
}

perform_final_verification() {
    echo -e "${GREEN}Final Verification${NC}"
    echo -e "${GREEN}==================${NC}"
    echo

    echo -e "${CYAN}${INFO}${NC} Performing final verification..."

    # Wait for service to be ready
    echo -e "${GRAY}  ${ARROW}${NC} Waiting for wireproxy service to be ready"
    if ! wait_for_service "wireproxy" 15; then
        echo -e "${RED}${CROSS}${NC} Service verification failed!"
        show_service_logs
        exit 1
    fi

    # Wait for port to be available
    echo -e "${GRAY}  ${ARROW}${NC} Waiting for port 40000 to be available"
    if ! wait_for_port "40000" 15; then
        echo -e "${RED}${CROSS}${NC} Port verification failed!"
        show_service_logs
        exit 1
    fi

    # Test WARP connection
    echo -e "${GRAY}  ${ARROW}${NC} Testing WARP connection"
    test_warp_connection

    echo -e "${GRAY}  ${ARROW}${NC} Cleaning up temporary files"
    rm -f /tmp/warp-account.conf >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Final verification completed successfully!"
    echo
}

display_completion_info() {
    echo -e "${PURPLE}===================${NC}"
    echo -e "${GREEN}${CHECK}${NC} SETUP COMPLETED!"
    echo -e "${PURPLE}===================${NC}"
    echo
    echo -e "${CYAN}Management Commands:${NC}"
    echo -e "${WHITE}• Check status: warp status${NC}"
    echo -e "${WHITE}• Test connection: warp test${NC}"
    echo -e "${WHITE}• Show information: warp info${NC}"
    echo -e "${WHITE}• View logs: warp logs${NC}"
    echo -e "${WHITE}• Uninstall: warp uninstall${NC}"
    echo
    echo -e "${CYAN}Test Commands:${NC}"
    echo -e "${WHITE}• curl --proxy socks5h://127.0.0.1:40000 https://ipinfo.io${NC}"
    echo -e "${WHITE}• curl --proxy socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace${NC}"
    echo
}

#================
# MENU FUNCTIONS
#================

show_main_menu() {
    echo
    echo -e "${PURPLE}===============${NC}"
    echo -e "${WHITE}WIREPROXY WARP${NC}"
    echo -e "${PURPLE}===============${NC}"
    echo
    echo -e "${CYAN}Please select an action:${NC}"
    echo
    echo -e "${GREEN}1.${NC} Install"
    echo -e "${YELLOW}2.${NC} Uninstall"
    echo -e "${RED}3.${NC} Exit"
    echo
}

handle_user_choice() {
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
                echo -e "${RED}${CROSS}${NC} Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

#================
# MAIN FUNCTIONS
#================

perform_installation() {
    echo
    echo -e "${PURPLE}=====================${NC}"
    echo -e "${WHITE}WireProxy WARP Setup${NC}"
    echo -e "${PURPLE}=====================${NC}"
    echo

    # Check if already installed
    if [ -f "/usr/bin/wireproxy" ] && [ -f "/etc/systemd/system/wireproxy.service" ]; then
        echo -e "${YELLOW}${WARNING}${NC} WireProxy WARP appears to be already installed."
        echo
        echo -ne "${YELLOW}Do you want to reinstall? (y/N): ${NC}"
        read -r REINSTALL
        
        if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Installation cancelled.${NC}"
            echo -e "${CYAN}Use 'warp status' to check current installation.${NC}"
            exit 0
        fi
        
        echo -e "${YELLOW}Proceeding with reinstallation...${NC}"
        echo
    fi

    set -e

    prepare_system
    setup_warp_account
    install_wireproxy
    create_configuration
    test_configuration
    setup_systemd_service
    create_management_script
    perform_final_verification
    display_completion_info
}

#==================
# MAIN ENTRY POINT
#==================

main() {
    # Check if script is run with parameters
    if [ "$1" = "uninstall" ] || [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
        ACTION="uninstall"
    elif [ "$1" = "install" ] || [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
        ACTION="install"
    else
        # Interactive menu
        show_main_menu
        handle_user_choice
    fi

    # Execute action
    if [ "$ACTION" = "uninstall" ]; then
        perform_uninstall
    else
        perform_installation
    fi
}

main
