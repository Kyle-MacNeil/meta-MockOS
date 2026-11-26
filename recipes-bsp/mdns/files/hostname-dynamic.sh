#!/bin/sh

BASE_HOSTNAME="pear"
IFACE="end0"
SYS_PATH="/sys/class/net/${IFACE}/address"
MAX_TRIES=30
COUNT=0

# 1. Poll until the network interface sysfs path exists (up to 30 seconds)
while [ ! -f "$SYS_PATH" ] && [ $COUNT -lt $MAX_TRIES ]; do
    sleep 1
    COUNT=$((COUNT + 1))
done

# 2. Extract MAC address if interface is found
if [ -f "$SYS_PATH" ]; then

	MAC_SUFFIX=$(cat "$SYS_PATH" | tr -d ':\n\r' | tail -c 6)
    
    if [ -n "$MAC_SUFFIX" ]; then
        NEW_HOSTNAME="${BASE_HOSTNAME}-${MAC_SUFFIX}"
        
        # Update system configuration
        echo "$NEW_HOSTNAME" > /etc/hostname
        echo -e "127.0.0.1\tlocalhost $NEW_HOSTNAME" > /etc/hosts
        
        # Apply immediately to kernel session
        hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || hostname "$NEW_HOSTNAME"
        echo "Dynamic Hostname set to: $NEW_HOSTNAME"
        exit 0
    fi
fi

echo "ERROR: Timed out waiting for network device $IFACE" >&2
exit 1