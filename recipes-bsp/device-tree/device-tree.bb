SUMMARY = "custom device tree"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit devicetree

COMPATIBLE_MACHINE = "(machine-name)"

KERNEL_INCLUDE += " ${STAGING_KERNEL_DIR}"

SRC_URI = "file://imx8mp-var-som-trax1.dts"

# Point cpp/dtc to the staged kernel source tree so "imx8mp-var-som.dtsi",
# "imx8mp.dtsi", and <dt-bindings/...> headers are found automatically.
KERNEL_INCLUDE = " \
    ${STAGING_KERNEL_DIR}/arch/${ARCH}/boot/dts \
    ${STAGING_KERNEL_DIR}/scripts/dtc/include-prefixes \
"

# Copy the compiled DTB into /boot/ (devicetree.bbclass defaults to /boot/devicetree/)
# so Mender and U-Boot find it at the expected path.
do_install:append() {
    install -d ${D}/boot
    install -m 0644 ${B}/custom-device-tree.dtb ${D}/boot/custom-device-tree.dtb
}

FILES:${PN} += "/boot/custom-device-tree.dtb"