#!/bin/sh
### First-boot eMMC Expansion Script ###

echo "=========================================="
echo "Expanding root partition to fill eMMC..."
echo "=========================================="

# 1. Expand partition 2 to 100% of the disk boundary
parted /dev/mmcblk0 resizepart 2 100%

# 2. Force the kernel to reload the partition table definitions
partprobe /dev/mmcblk0

# 3. Perform live on-line resize of the ext4 filesystem
resize2fs /dev/mmcblk0p2

# 4. Disable this systemd unit so it never executes on subsequent boots
systemctl disable expand-rootfs.service

echo "=========================================="
echo "eMMC Expansion Complete!"
echo "=========================================="
