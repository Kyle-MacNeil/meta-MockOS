SUMMARY = "Automated eMMC storage expansion service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://expand-rootfs.sh \
    file://expand-rootfs.service \
"

# Enforce runtime dependencies so bitbake builds parted and resize2fs into your image
RDEPENDS:${PN} = "parted e2fsprogs-resize2fs"

inherit systemd

SYSTEMD_SERVICE:${PN} = "expand-rootfs.service"

do_install() {
    # Install the script into /usr/bin
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/expand-rootfs.sh ${D}${bindir}/expand-rootfs.sh

    # Install the systemd service file
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/expand-rootfs.service ${D}${systemd_system_unitdir}/expand-rootfs.service
}
