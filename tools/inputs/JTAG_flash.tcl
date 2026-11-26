#Version 2

if {[info exists BASE_DIR]} {
    puts "Using the following base directory ${BASE_DIR}"
} else {
    puts "Error: BASE_DIR is not defined."
	exit 1
}

# Ensure the base directory ends with a slash for easy path concatenation
if {[string last "/" $BASE_DIR] != [string length $BASE_DIR] - 1} {
    set BASE_DIR "$BASE_DIR/"
}

connect -url tcp:10.0.0.2:3121 

puts "--- 1. Standard JTAG setup ---"
targets -set -filter {name =~ "PSU"}


puts "--- 2. Loading PMU ---"
targets -set -filter {name =~ "MicroBlaze PMU"}
dow ${BASE_DIR}Binaries/pmufw.elf
con


puts "--- 3. Loading and Executing FSBL on A53 ---"
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor
dow ${BASE_DIR}Binaries/fsbl.elf
con
after 5000
stop

puts "--- 4. Run TF-A ---"
dow ${BASE_DIR}Binaries/bl31.elf

puts "--- 5. Run u-boot --- "
dow ${BASE_DIR}Binaries/u-boot.elf

targets -set -filter {name =~ "Cortex-A53 #0"}

con
after 10000
stop

puts "--- 6. Loading Kernel Image to DRAM (0xX0000000) ---"
set KERNEL_ADDR "0xX0000000"
dow -data ${BASE_DIR}Binaries/Image $KERNEL_ADDR

puts "--- 7. Loading Device Tree Blob (DTB) to DRAM (0xX0000000) ---"
set DTB_ADDR "0xX0000000"
dow -data ${BASE_DIR}Binaries/system.dtb $DTB_ADDR

puts "--- 8. Loading Ramdisk Root Filesystem to DRAM (0xX0000000) ---"
set RAMDISK_ADDR "0xX0000000"
dow -data ${BASE_DIR}Binaries/rootfs.cpio.gz.u-boot $RAMDISK_ADDR

puts "--- 9. Final U-Boot Execution ---"
con

puts "JTAG boot sequence complete. U-Boot should now be running."
puts "You must immediately execute U-Boot commands on the serial terminal to boot Linux."
after 10000


