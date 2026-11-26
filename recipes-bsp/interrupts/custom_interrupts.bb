DESCRIPTION = "Builds and adds the interrutp module"
LICENSE = "GPL-2.0-only" 
LIC_FILES_CHKSUM = "file://LICENSE;md5=7deccc738f37d7c9fce38a7e189eca2f"

SRC_URI = "file://interruptmodule.c \
           file://Makefile \
		   file://LICENSE"

S = "${WORKDIR}"

# Inherit the kernel module build class
inherit module

KERNEL_MODULE_AUTOLOAD += "custom-interrupts"