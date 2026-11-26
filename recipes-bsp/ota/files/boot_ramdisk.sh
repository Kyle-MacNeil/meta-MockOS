#!/bin/bash

# Define usage menu
usage() {
    echo "Usage: sudo $0 [-c IP_ADDRESS] [dev [-c CUSTOM_IP] [-p HTTP_PORT]]" >&2
    echo "" >&2
    echo "Options / Arguments:" >&2
    echo "  (no arguments)                 : Resolve and use production server (UPDATER.local) via TFTP" >&2
    echo "  -c IP_ADDRESS                  : Use production workflow with a custom TFTP Server IP" >&2
    echo "  dev                            : Use the development HTTP server (default IP: 192.168.200.117, Port: 8000)" >&2
    echo "  dev -c {IP}                    : Use development workflow with a custom HTTP Server IP" >&2
    echo "  dev -c {IP} -p {PORT}          : Use development workflow with custom HTTP Server IP and Port" >&2
    echo "  dev -p {PORT}                  : Use development workflow with default HTTP IP and custom Port" >&2
    exit 1
}

# Check if the script is being run as root (sudo)
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo or as root." >&2
    exit 1
fi

# Initialize argument flag variables
CUSTOM_IP=""
HTTP_PORT="8000"
IS_DEV=0

# Helper IPv4 validation function
validate_ipv4() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: '$ip' is not a valid IPv4 address." >&2
        exit 1
    fi
}

# Helper Port validation function
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Error: '$port' is not a valid HTTP port (1-65535)." >&2
        exit 1
    fi
}

# Parse options using getopts
while getopts ":c:p:h" opt; do
  case ${opt} in
    c)
      CUSTOM_IP="$OPTARG"
      validate_ipv4 "$CUSTOM_IP"
      ;;
    p)
      echo "Error: Option -p is only valid when using 'dev' mode." >&2
      usage
      ;;
    h)
      usage
      ;;
    \?)
      echo "Error: Invalid option -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Error: Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done

# Shift processed option flags out of the positional parameters
shift $((OPTIND - 1))

# Process positional arguments
if [ $# -gt 0 ]; then
    if [ "$1" = "dev" ]; then
        IS_DEV=1
        shift 1
        
        # Parse options following the 'dev' parameter
        OPTIND=1
        while getopts ":c:p:h" opt; do
            case ${opt} in
                c)
                    CUSTOM_IP="$OPTARG"
                    validate_ipv4 "$CUSTOM_IP"
                    ;;
                p)
                    HTTP_PORT="$OPTARG"
                    validate_port "$HTTP_PORT"
                    ;;
                h)
                    usage
                    ;;
                \?)
                    echo "Error: Invalid option -$OPTARG in dev mode." >&2
                    usage
                    ;;
                :)
                    echo "Error: Option -$OPTARG requires an argument." >&2
                    usage
                    ;;
            esac
        done
        shift $((OPTIND - 1))
        
        if [ $# -ne 0 ]; then
            echo "Error: Unexpected argument '$1'." >&2
            usage
        fi
    else
        echo "Error: Invalid positional argument '$1'." >&2
        usage
    fi
fi

TARGET_DISK="/dev/mmcblk0"

echo "=== Checking if target disk is mounted ==="
if ! lsblk -no MOUNTPOINTS "$TARGET_DISK" | grep -q '[a-zA-Z0-9]'; then
    echo "ramdisk is already running, exiting script..."
    exit 1
fi
# The script will continue here if mmcblk0 IS mounted
echo "Target disk is mounted. Continuing with the script..."

TARGET_IP="${CUSTOM_IP:-$TFTP_SERVER}"

if [ -n "$TARGET_IP" ]; then
    # Parse the 'src <IP>' output from ip route get, regardless of field position
    IP_ADDR=$(ip -4 route get "$TARGET_IP" 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}')
fi

# Fallback 1: Get the source IP from the default route table if present
if [ -z "$IP_ADDR" ]; then
    IP_ADDR=$(ip -4 route show default 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}' | head -n 1)
fi

# Fallback 2: Get the first non-loopback IPv4 assigned to an active interface (BusyBox grep compatible)
if [ -z "$IP_ADDR" ]; then
    IP_ADDR=$(ip -4 addr show up 2>/dev/null | grep -v '127.0.0.1' | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
fi

# Final Check: Ensure a valid IPv4 address was actually found
if [[ ! "$IP_ADDR" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [ "$IP_ADDR" = "0.0.0.0" ]; then
    echo "Error: Could not automatically detect an active network IP address." >&2
    echo "Please ensure your network interface is UP and has an assigned IP address." >&2
    exit 1
fi

# Dynamically calculate the Gateway IP and Netmask
if [[ "$IP_ADDR" =~ ^169\.254\. ]]; then
    NETMASK="255.255.0.0" # Link-local scopes strictly require a 16-bit broad netmask
    GATEWAY_IP="0.0.0.0"
else
    NETMASK="255.255.255.0"
    GATEWAY_IP=$(echo "$IP_ADDR" | sed 's/\.[0-9]*$/\.1/')
fi

# Define file paths
TXT_FILE="/boot/network_ramboot.txt"
SCR_FILE="/boot/boot.scr"
BACKUP_FILE="/boot/boot_orig.scr"
INDEX_FILE="index.txt"
LOCAL_INDEX="/tmp/remote_files.txt"
LOCAL_JSON="/tmp/remote_files.json"

# HTTP Server Configuration
HTTP_HOST="UPDATER.local"
HTTP_SERVER=""

# Environment logic
if [ "$IS_DEV" -eq 1 ]; then
    echo "Development mode active. Skipping hostname resolution..."
    HTTP_SERVER="${CUSTOM_IP:-192.168.200.117}"
elif [ -n "$CUSTOM_IP" ]; then
    echo "Production mode active (Custom IP override: ${CUSTOM_IP})."
    
    # Basic IPv4 validation check
    if [[ ! "$CUSTOM_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Error: Provided custom IP '${CUSTOM_IP}' is not a valid IPv4 address." >&2
        exit 1
    fi
    
    TFTP_SERVER="$CUSTOM_IP"
else
    echo "Production mode active. Resolving hostname '${HTTP_HOST}' to IP address..."
    
    # Attempt resolution via avahi-resolve (standard for .local mDNS on Linux)
    RESOLVED_IP=$(avahi-resolve -4 -n "$HTTP_HOST" 2>/dev/null | awk '{print $2}')
    
    # Fallback to getent hosts if avahi-resolve isn't present
    if [ -z "$RESOLVED_IP" ]; then
        RESOLVED_IP=$(getent ahosts "$HTTP_HOST" | awk '/STREAM/ {print $1; exit}')
    fi
    
    # Fallback to standard ping resolve if others fail
    if [ -z "$RESOLVED_IP" ]; then
        RESOLVED_IP=$(getent hosts "$HTTP_HOST" | awk '{print $1; exit}')
    fi

    if [ -z "$RESOLVED_IP" ]; then
        echo "Error: Failed to resolve hostname '${HTTP_HOST}'." >&2
        echo "Please verify that the server is powered on and connected to the same LAN." >&2
        exit 1
    fi
    
    echo "Successfully resolved ${HTTP_HOST} to ${RESOLVED_IP}"

    # --- CHECK: Same subnet check (Mask 255.255.0.0 /16) ---
    LOCAL_SUBNET=$(echo "$IP_ADDR" | cut -d. -f1-2)
    TARGET_SUBNET=$(echo "$RESOLVED_IP" | cut -d. -f1-2)

    if [ "$LOCAL_SUBNET" != "$TARGET_SUBNET" ]; then
        echo "Error: Local device IP ($IP_ADDR) and $HTTP_HOST ($RESOLVED_IP) are not on the same subnet." >&2
        echo "Aborting execution." >&2
        exit 1
    fi
    echo "Subnet match check passed (255.255.0.0 match: ${LOCAL_SUBNET}.x.x)."

    TFTP_SERVER="$RESOLVED_IP"
fi

HTTP_URL="http://${HTTP_SERVER}:${HTTP_PORT}"

# File parsing logic depending on Dev vs. Prod (Caddy JSON) mode
if [ "$IS_DEV" -eq 1 ]; then
    # --- DEVELOPMENT MODE: Fallback to old index.txt ---
    echo "Fetching plain-text file index from dev HTTP server (${HTTP_URL}/${INDEX_FILE})...."
    curl -s -f "${HTTP_URL}/${INDEX_FILE}" -o "$LOCAL_INDEX"

    if [ ! -f "$LOCAL_INDEX" ]; then
        echo "Error: Could not retrieve file list ($INDEX_FILE) from dev HTTP server." >&2
        exit 1
    fi

    # Parse plain-text file using grep
    IMAGE=$(grep -E '^Image_[0-9]+\.[0-9]+\.[0-9]+$' "$LOCAL_INDEX" | sort -V | tail -n 1)
    ROOTFS=$(grep -E '^rootfs_[0-9]+\.[0-9]+\.[0-9]+\.cpio.gz.u-boot$' "$LOCAL_INDEX" | sort -V | tail -n 1)
    DEVICE_TREE=$(grep -E '^system_[0-9]+\.[0-9]+\.[0-9]+\.dtb$' "$LOCAL_INDEX" | sort -V | tail -n 1)
else
    # --- PRODUCTION MODE ---
    echo "Fetching file index from TFTP server (${TFTP_SERVER})..."
    tftp -g -r "$INDEX_FILE" -l "$LOCAL_INDEX" "$TFTP_SERVER"

    if [ ! -f "$LOCAL_INDEX" ]; then
        echo "Error: Could not retrieve file list ($INDEX_FILE) from TFTP server." >&2
        exit 1
    fi
    
    # remove null bytes (\0), carriage returns (\r), and UTF-16 BOM characters
    tr -d '\0\r' < "$LOCAL_INDEX" | sed 's/^[^\a-zA-Z0-9_]*//' > "${LOCAL_INDEX}.tmp" && mv "${LOCAL_INDEX}.tmp" "$LOCAL_INDEX"

    IMAGE=$(grep -E '^Image_[0-9]+\.[0-9]+\.[0-9]+$' "$LOCAL_INDEX" | sort -V | tail -n 1)
    ROOTFS=$(grep -E '^rootfs_[0-9]+\.[0-9]+\.[0-9]+\.cpio.gz.u-boot$' "$LOCAL_INDEX" | sort -V | tail -n 1)
    DEVICE_TREE=$(grep -E '^system_[0-9]+\.[0-9]+\.[0-9]+\.dtb$' "$LOCAL_INDEX" | sort -V | tail -n 1)
fi

# Ensure all three assets were found before building the script
if [ -z "$IMAGE" ] || [ -z "$ROOTFS" ] || [ -z "$DEVICE_TREE" ]; then
    echo "Error: One or more required boot files could not be found." >&2
    echo "  Found Image:       ${IMAGE:-[NOT FOUND]}" >&2
    echo "  Found Rootfs:      ${ROOTFS:-[NOT FOUND]}" >&2
    echo "  Found Device Tree: ${DEVICE_TREE:-[NOT FOUND]}" >&2
    exit 1
fi

echo "Network Parameters Detected:"
echo "  Target Server IP: ${TFTP_SERVER:-$HTTP_SERVER}"
if [ "$IS_DEV" -eq 1 ]; then
    echo "  Target HTTP Port: $HTTP_PORT"
fi
echo "  Detected Host IP: $IP_ADDR"
echo "  Assumed Netmask:  $NETMASK"
echo "  Calculated GW:    $GATEWAY_IP"
echo "-------------------------------------------------"

# Backup Logic
if [ ! -f "$BACKUP_FILE" ]; then
    if [ -f "$SCR_FILE" ]; then
        echo "Backup '$BACKUP_FILE' not found. Backing up existing boot.scr..."
        mv "$SCR_FILE" "$BACKUP_FILE"
    else
        echo "Error. No existing '$SCR_FILE' found to backup. Please find the boot.scr file. Exiting..."
        exit 1
    fi
else
    echo "Backup '$BACKUP_FILE' already exists. Skipping backup step."
fi

echo "-------------------------------------------------"

# Generate the raw text configuration file
echo "Creating source script text file at $TXT_FILE..."

if [ "$IS_DEV" -eq 1 ]; then
    # --- DEV MODE (Internal Use) ---
    cat << EOF > "$TXT_FILE"
echo "================================================="
echo "Carrier Board: Forcing HTTP RAM Boot Sequence (DEV)"
echo "================================================="
setenv fdt_addr_r     0xX0000000
setenv kernel_addr_r  0xX0000000
setenv ramdisk_addr_r 0xX0000000

setenv autoload no
dhcp

setenv serverip ${HTTP_SERVER}
setenv httpdstp ${HTTP_PORT}

echo "Downloading assets via U-Boot wget..."

wget \$kernel_addr_r \$serverip:/${IMAGE}
wget \$fdt_addr_r \$serverip:/${DEVICE_TREE}
wget \$ramdisk_addr_r \$serverip:/${ROOTFS}
setenv ramdisk_size \$filesize

setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/ram0 rw ip=dhcp"

booti \$kernel_addr_r \$ramdisk_addr_r:\$ramdisk_size \$fdt_addr_r
EOF

elif [ -n "$CUSTOM_IP" ]; then
    # --- PRODUCTION MODE (Static Host IP via -c) ---
    cat << EOF > "$TXT_FILE"
echo "================================================="
echo "Carrier Board: Forcing TFTP RAM Boot Sequence (STATIC IP)"
echo "================================================="
setenv fdt_addr_r     0xX0000000
setenv kernel_addr_r  0xX0000000
setenv ramdisk_addr_r 0xX0000000

setenv ipaddr        ${IP_ADDR}
setenv netmask       ${NETMASK}
setenv gatewayip     ${GATEWAY_IP}
setenv serverip      ${TFTP_SERVER}

# Direct U-Boot network traffic to use the second ethernet port (end1)
setenv ethact        eth1

tftpboot \${kernel_addr_r} $IMAGE
tftpboot \${fdt_addr_r} $DEVICE_TREE
tftpboot \${ramdisk_addr_r} $ROOTFS

# Instruct Linux kernel autoconf to assign static parameters to end1
setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/ram0 rw ip=${IP_ADDR}::${GATEWAY_IP}:${NETMASK}::eth1:off"

booti \${kernel_addr_r} \${ramdisk_addr_r}:\${filesize} \${fdt_addr_r}
EOF

else
    # --- PRODUCTION MODE (OTA) ---
    cat << EOF > "$TXT_FILE"
echo "================================================="
echo "Carrier Board: Forcing TFTP RAM Boot Sequence (OTA)"
echo "================================================="
setenv fdt_addr_r     0xX0000000
setenv kernel_addr_r  0xX0000000
setenv ramdisk_addr_r 0xX0000000

setenv autoload no
echo "Attempting DHCP..."
if dhcp; then
    echo "DHCP successful!"
    setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/ram0 rw ip=dhcp"
else
    echo "DHCP failed. Falling back to Link-Local configuration..."
    setenv netmask ${NETMASK}
    linklocal
    setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/ram0 rw ip=none"
fi

setenv serverip       $TFTP_SERVER

tftpboot \${kernel_addr_r} $IMAGE
tftpboot \${fdt_addr_r} $DEVICE_TREE
tftpboot \${ramdisk_addr_r} $ROOTFS

setenv bootargs "earlycon console=ttyPS0,115200 clk_ignore_unused root=/dev/ram0 rw ip=none"

booti \${kernel_addr_r} \${ramdisk_addr_r}:\${filesize} \${fdt_addr_r}
EOF
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to write to '$TXT_FILE'." >&2
    exit 1
fi

# Compile the text file into a U-Boot image using mkimage
echo "Compiling $TXT_FILE into $SCR_FILE..."
mkimage -A arm64 -O linux -T script -C none -a 0 -e 0 -n "IP Boot" -d "$TXT_FILE" "$SCR_FILE"

if [ $? -ne 0 ]; then
    echo "Error: mkimage compilation failed." >&2
    exit 1
fi

echo "-------------------------------------------------"

# Final verification and reboot
if [ $? -eq 0 ]; then
    echo "-------------------------------------------------"
    echo "Success: U-Boot binary script generated successfully at $SCR_FILE."
    echo "Please reboot the system now..."
else
    echo "Error: mkimage compilation failed." >&2
    exit 1
fi