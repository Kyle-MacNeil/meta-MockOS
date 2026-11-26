SUMMARY = "Custom Production Image for custom device"
DESCRIPTION = "Image for the Production release."
LICENSE = "MIT"

IMAGE_FSTYPES += "wic"

EXTRA_IMAGE_FEATURES += "tools-debug"

# -----START: Entries carried over from vendor base image (scarthgap)-----
inherit core-image

IMAGE_FEATURES += " \
    splash \
    ssh-server-openssh \
    hwcodecs \
    debug-tweaks \
    nfs-client \
    tools-debug \
    tools-testapps \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston', \
       bb.utils.contains('DISTRO_FEATURES',     'x11', 'x11-base x11-sato', \
                                                       '', d), d)} \
"

CORE_IMAGE_EXTRA_INSTALL += " \
	packagegroup-core-full-cmdline \
	packagegroup-tools-bluetooth \
	packagegroup-imx-tools-audio \
	packagegroup-fsl-tools-gpu-external \
	packagegroup-fsl-tools-testapps \
	packagegroup-fsl-tools-benchmark \
	packagegroup-fsl-gstreamer1.0 \
	packagegroup-fsl-gstreamer1.0-full \
	packagegroup-fsl-isp \
"

systemd_disable_vt () {
    rm ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/getty.target.wants/getty@tty*.service
}

IMAGE_PREPROCESS_COMMAND:append = " ${@ 'systemd_disable_vt;' if bb.utils.contains('DISTRO_FEATURES', 'systemd', True, False, d) and bb.utils.contains('USE_VT', '0', True, False, d) else ''} "

# ----- End -----


IMAGE_INSTALL:append = " \
python3 \
    python3-awsiotpythonsdk \
    python3-pykarbon \
    python3-numpy \
    python3-boto3 \
    python3-requests \
    dtc \
    gpsd \
    gps-utils \
    libgps \
    gpsd-gpsctl \
    packagegroup-core-buildessential \
    vim \
    tzdata \
    i2c-tools \
    libgpiod libgpiod-tools \
    libgpiod-dev \
"

IMAGE_INSTALL:remove = " \
    dropbear \
    packagegroup-core-ssh-dropbear "