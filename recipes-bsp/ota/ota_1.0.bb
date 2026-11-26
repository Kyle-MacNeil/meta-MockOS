SUMMARY = "Recipe to place scripts in rootfs for ota"
LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
	file://boot_ramdisk.sh \
	file://ramdisk_emmc_flash.sh \
"

RDEPENDS:${PN} += "bash"

S = "${WORKDIR}"

do_install() {
    # Create the destination directories in the image
    install -d ${D}/etc/ota

    # Install the files
    # ${D} represents the destination (image root)
	install -m 0755 ${S}/boot_ramdisk.sh  ${D}/etc/ota
	install -m 0755 ${S}/ramdisk_emmc_flash.sh  ${D}/etc/ota

}

# Ensure the files are packaged into the final image
FILES:${PN} += " \
	/etc/ota/boot_ramdisk.sh \
	/etc/ota/ramdisk_emmc_flash.sh \
"
