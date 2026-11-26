SUMMARY = "Recipe to install and enable WASP services"
LICENSE = "CLOSED"

inherit systemd features_check

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://clear_all_data.service \
	file://clear_doorbell.service \
    file://clear_all_data \
	file://clear_doorbell \
	file://subagent.service \
	file://subagent \
	file://firstboot-setup.service \
	file://setup \
	file://setup.sh \
	file://setup-env \
	file://ddr_setup.service \
	file://redcore_mac_setup.sh \
	file://redcore_mac_setup.service \
"

# Runtime dependencies
RDEPENDS:${PN} += " \
    openssl \
    jsoncpp \
    paho-mqtt-c \
    paho-mqtt-cpp \
"


# Prevent Yocto from trying to strip the binaries again (which can corrupt them)
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"


# Set the systemd service names to be enabled
SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = " \
    clear_all_data.service \
	clear_doorbell.service \
	firstboot-setup.service \
	ddr_setup.service \
	redcore_mac_setup.service \
"

# Define where the files will be installed in the rootfs
do_install() {
    # 1. Create directories in the image 
    install -d ${D}/opt/custom_user
    install -d ${D}${systemd_system_unitdir}
	install -d ${D}/etc/default
	install -d ${D}/usr/sbin
	install -d ${D}/usr/bin
	install -d ${D}/var/lib/custom-binary

    # 2. Install the executables to their path desitination 
	install -m 0755 ${WORKDIR}/clear_all_data ${D}/opt/custom_user/
	install -m 0755 ${WORKDIR}/clear_doorbell ${D}/opt/custom_user/
	install -m 0600 ${WORKDIR}/custom-binary ${D}/etc/default/
	install -m 0755 ${WORKDIR}/subagent ${D}/usr/bin/
	install -m 0755 ${WORKDIR}/redcore_mac_setup.sh ${D}/usr/sbin/
	
    
    # 3. Install the service files 
	install -m 0644 ${WORKDIR}/clear_all_data.service ${D}${systemd_system_unitdir}/
	install -m 0644 ${WORKDIR}/clear_doorbell.service ${D}${systemd_system_unitdir}/
	install -m 0644 ${WORKDIR}/firstboot-setup.service ${D}${systemd_system_unitdir}/
	install -m 0644 ${WORKDIR}/subagent.service ${D}${systemd_system_unitdir}/
	install -m 0644 ${WORKDIR}/ddr_setup.service ${D}${systemd_system_unitdir}/
	install -m 0644 ${WORKDIR}/redcore_mac_setup.service ${D}${systemd_system_unitdir}/
}

# Ensure the files are included in the package
FILES:${PN} += " \
    /opt/wasp/clear_all_data \
	/opt/wasp/clear_doorbell \
    ${systemd_system_unitdir}/clear_all_data.service \
	${systemd_system_unitdir}/clear_doorbell.service \
	${systemd_system_unitdir}/subagent.service \
	${systemd_system_unitdir}/firstboot-setup.service \
	/usr/bin/subagent \
	${systemd_system_unitdir}/ddr_setup.service \
	/usr/sbin/redcore_mac_setup.sh \
	${systemd_system_unitdir}/redcore_mac_setup.service \
"

# Specify that this package depends on systemd
REQUIRED_DISTRO_FEATURES = "systemd"