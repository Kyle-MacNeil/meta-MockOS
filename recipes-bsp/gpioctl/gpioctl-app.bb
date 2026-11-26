DESCRIPTION = "GPIO control application"
LICENSE = "CLOSED"

SRC_URI = "file://gpioctl"


FILES:${PN} += "${bindir}/gpioctl"
RDEPENDS:${PN} = "libgpiod"
 

do_install() {
  install -d ${D}${bindir}
  install -m 0755 ${UNPACKDIR}/gpioctl ${D}${bindir}
}
