#!/bin/bash
set -euo pipefail

# === Usage Function ===
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

# === Helper Functions ===
# Helper to convert IPv4 string (e.g., 10.0.0.2) to 32-bit integer
ip_to_int() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

check_subnet() {
    local target_ip="$1"
    
    # Extract local outgoing IP reliably
    local ip_addr
    ip_addr=$(ip -4 route get "$target_ip" 2>/dev/null | awk -F'src ' '{print $2}' | awk '{print $1}')

    # Fallback to first global IP if primary lookup is empty or "0"
    if [ -z "$ip_addr" ] || [ "$ip_addr" = "0" ]; then
        ip_addr=$(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
    fi

    if [ -z "$ip_addr" ]; then
        echo "ERROR: Could not automatically detect an active network IP address." >&2
        exit 1
    fi

    # Retrieve CIDR prefix length (e.g., "24" from "10.0.0.2/24") for the matching local IP interface
    local cidr
    cidr=$(ip -4 addr show | grep -w "$ip_addr" | awk '{print $2}' | cut -d/ -f2 | head -n 1)

    # Fallback to default /24 if CIDR mask extraction fails
    if [ -z "$cidr" ]; then
        cidr=24
    fi

    # Calculate netmask bitmask dynamically based on CIDR
    local mask=$(( 0xFFFFFFFF << (32 - cidr) & 0xFFFFFFFF ))
    
    # Convert local and target IPs to integers
    local local_int target_int
    local_int=$(ip_to_int "$ip_addr")
    target_int=$(ip_to_int "$target_ip")

    # Perform bitwise AND to get network addresses
    local local_net target_net
    local_net=$(( local_int & mask ))
    target_net=$(( target_int & mask ))

    if [ "$local_net" -ne "$target_net" ]; then
        echo "ERROR: Local device IP ($ip_addr) and target IP ($target_ip) are not on the same subnet (/$cidr)." >&2
        echo "Aborting execution." >&2
        exit 1
    fi
    
    echo "Subnet match check passed (Local IP: $ip_addr, Target IP: $target_ip on /$cidr subnet)."
}

# Helper IPv4 validation function
validate_ipv4() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "ERROR: Provided custom IP '${ip}' is not a valid IPv4 address format." >&2
        exit 1
    fi
}

# Helper Port validation function
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "ERROR: '$port' is not a valid HTTP port (1-65535)." >&2
        exit 1
    fi
}

# === Argument Handling ===
# Default server configuration
SERVER_HOST="UPDATER.local"
SERVER_PORT="8000"
SERVER_IP=""
CUSTOM_IP=""
IS_DEV=0

# Parse options using getopts
while getopts ":c:p:h" opt; do
  case ${opt} in
    c)
      CUSTOM_IP="$OPTARG"
      validate_ipv4 "$CUSTOM_IP"
      ;;
    p)
      echo "ERROR: Option -p is only valid when using 'dev' mode." >&2
      usage
      ;;
    h)
      usage
      ;;
    \?)
      echo "ERROR: Invalid option -$OPTARG" >&2
      usage
      ;;
    :)
      echo "ERROR: Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done

# Shift processed option flags out of positional parameters
shift $((OPTIND - 1))

# Parse positional arguments
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
                    SERVER_PORT="$OPTARG"
                    validate_port "$SERVER_PORT"
                    ;;
                h)
                    usage
                    ;;
                \?)
                    echo "ERROR: Invalid option -$OPTARG in dev mode." >&2
                    usage
                    ;;
                :)
                    echo "ERROR: Option -$OPTARG requires an argument." >&2
                    usage
                    ;;
            esac
        done
        shift $((OPTIND - 1))

        if [ $# -ne 0 ]; then
            echo "ERROR: Unexpected argument '$1'." >&2
            usage
        fi
    else
        echo "ERROR: Invalid argument '$1'." >&2
        usage
    fi
fi

# Apply parsed arguments to environment configuration
if [ "$IS_DEV" -eq 1 ]; then
    echo "Development mode active. Skipping hostname resolution and subnet check..."
    SERVER_IP="${CUSTOM_IP:-192.168.200.117}"
elif [ -n "$CUSTOM_IP" ]; then
    echo "Production mode active (Custom IP override: ${CUSTOM_IP})."
    
    # Perform subnet match check for custom IP
    check_subnet "$CUSTOM_IP"
    
    SERVER_IP="$CUSTOM_IP"
else
    echo "Production mode active. Resolving hostname '${SERVER_HOST}' to IP address..."
    IS_DEV=0
    
    # Attempt resolution via avahi-resolve (standard for .local mDNS on Linux)
    RESOLVED_IP=$(avahi-resolve -4 -n "$SERVER_HOST" 2>/dev/null | awk '{print $2}')
    
    # Fallback to getent hosts if avahi-resolve isn't present
    if [ -z "$RESOLVED_IP" ]; then
        RESOLVED_IP=$(getent ahosts "$SERVER_HOST" | awk '/STREAM/ {print $1; exit}')
    fi
    
    # Fallback to standard ping resolve if others fail
    if [ -z "$RESOLVED_IP" ]; then
        RESOLVED_IP=$(getent hosts "$SERVER_HOST" | awk '{print $1; exit}')
    fi

    if [ -z "$RESOLVED_IP" ]; then
        echo "ERROR: Failed to resolve hostname '${SERVER_HOST}'." >&2
        echo "Please verify that the server is powered on and connected to the same LAN." >&2
        exit 1
    fi
    
    echo "Successfully resolved ${SERVER_HOST} to ${RESOLVED_IP}"

    # Perform subnet match check for resolved IP
    check_subnet "$RESOLVED_IP"

    SERVER_IP="$RESOLVED_IP"
fi

# Construct final server URL
SERVER_URL="http://${SERVER_IP}:${SERVER_PORT}"
TARGET_DISK="/dev/mmcblk0"

echo "=== Checking if target disk is mounted ==="
if lsblk -no MOUNTPOINTS "$TARGET_DISK" | grep -q '[a-zA-Z0-9]'; then
    echo "ERROR: Target disk ${TARGET_DISK} (or one of its partitions) is currently mounted!" >&2
    echo "Aborting flash to prevent major data corruption." >&2
    exit 1
fi

echo "=== Querying server ($SERVER_URL) for the latest image version ==="

if [ "$IS_DEV" -eq 1 ]; then
    # --- DEVELOPMENT MODE: Parse the Python HTTP server HTML directory listing ---
    echo "Development Mode: Fetching HTML list..."
    LATEST_FILE=$(wget -q -O - "$SERVER_URL" | \
                  grep -o 'custom_image_[0-9.]*\.wic' | \
                  sort -V | \
                  tail -n 1)
else
    # --- PRODUCTION MODE: Query Caddy JSON directly ---
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: 'jq' utility is required in Production Mode to parse Caddy's JSON response." >&2
        echo "Please run: sudo apt update && sudo apt install jq" >&2
        exit 1
    fi

    echo "Production Mode: Querying Caddy JSON API..."
    
    # Fetch the directory as JSON using custom Accept header
    JSON_DATA=$(wget -q -S --header="Accept: application/json" -O - "$SERVER_URL")

    if [ -z "$JSON_DATA" ]; then
        echo "ERROR: Did not receive JSON payload from Caddy server." >&2
        exit 1
    fi

    # Extract .name fields, filter for 'custom_image_x.x.x.wic', sort naturally, and take the newest
    LATEST_FILE=$(echo "$JSON_DATA" | \
                  jq -r '.[].name' | \
                  grep -E '^custom_image_[0-9.]*\.wic$' | \
                  sort -V | \
                  tail -n 1)
fi

if [ -z "$LATEST_FILE" ]; then
    echo "ERROR: No matching custom_image_x.x.x.wic files found on $SERVER_URL" >&2
    exit 1
fi

HTTP_URL="${SERVER_URL}/${LATEST_FILE}"
echo "Targeting latest image: $LATEST_FILE"

# === HTTP Streaming to Disk ===
echo "Streaming image via HTTP directly to eMMC ($TARGET_DISK)..."
if wget -q -O - "$HTTP_URL" | \
   dd of="$TARGET_DISK" bs=4M status=progress iflag=fullblock conv=fsync; then
    sync
    echo "=== SUCCESS: Flash completed ==="
else
    echo "ERROR: Streaming failed!" >&2
    exit 1
fi