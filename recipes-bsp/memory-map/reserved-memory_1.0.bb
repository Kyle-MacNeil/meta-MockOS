DESCRIPTION = "Linux kernel module to map reserved DDR memory (0x8_0000_0000, 4GiB) to user space via mmap."
LICENSE = "GPL-2.0-only" 
LIC_FILES_CHKSUM = "file://LICENSE;md5=7deccc738f37d7c9fce38a7e189eca2f"

SRC_URI = "file://reserved_memory.c \
           file://Makefile \
		   file://LICENSE"

S = "${WORKDIR}"

# Inherit the kernel module build class
inherit module

KERNEL_MODULE_AUTOLOAD += "reserved_memory"