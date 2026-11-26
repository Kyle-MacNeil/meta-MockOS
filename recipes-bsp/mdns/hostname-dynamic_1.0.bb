SUMMARY = "Dynamic hostname assignment based on end0 MAC"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://hostname-dynamic.sh \
    file://hostname-dynamic.service \
"

SYSTEMD_SERVICE:${PN} = "hostname-dynamic.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/hostname-dynamic.sh ${D}${bindir}/hostname-dynamic.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/hostname-dynamic.service ${D}${systemd_system_unitdir}/hostname-dynamic.service
}

FILES:${PN} += " \
    ${bindir}/hostname-dynamic.sh \
    ${systemd_system_unitdir}/hostname-dynamic.service \
"

RDEPENDS:${PN} += "bash coreutils systemd"
