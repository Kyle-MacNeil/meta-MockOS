# syntax=docker/dockerfile:1

FROM --platform=linux/amd64 ubuntu:22.04

ARG INSTALL_TARGET_DIR=/opt/REDACTED
ARG HOST_TOOL_ARCHIVE_NAME
ARG REDACTED_VERSION=REDACTED
ARG HOST_TOOL_ARCHIVE_EXTENSION=.tar

ENV REDACTED_INSTALL_LOCATION=$INSTALL_TARGET_DIR
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN echo "dash dash/sh boolean false" | debconf-set-selections \
    && DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    build-essential \
    ca-certificates \
    chrpath \
    cpio \
    default-jre \
    diffstat \
    dos2unix \
	doxygen \
    expect \
    fakeroot \
    gawk \
    gcc \
    gcc-multilib \
    git \
    gnupg \
    google-perftools \
	graphviz \
    gzip \
    iproute2 \
    less \
    libglib2.0-dev \
    libgtk2.0-0 \
    libgtk2.0-dev \
    libncurses5-dev \
    libsdl1.2-dev \
    libselinux1 \
    libssl-dev \
    libtinfo5 \
    libtool \
    libtool-bin \
    locales \
    lsb-release \
    make \
    net-tools \
    pax \
	pandoc \
    python3-gi \
	python3-pip \
	python3-venv \
    rsync \
    screen \
    socat \
	tcl \
    texinfo \
    tofrodos \
    unzip \
    wget \
    xterm \
    xvfb \
    zlib1g-dev \
	kconfig-frontends \
    liblz4-tool \
    python3-yaml \
    wget \
    x11-utils \
    zip \
    zstd \
	parted \
	mtools \
	rclone \
    && rm -rf /var/lib/apt/lists/*
	
# To avoid errors with gspread
RUN pip3 install --no-cache-dir gspread

# To ensure tar 1.35 is used instead of tar 1.34
RUN wget https://ftp.gnu.org/gnu/tar/tar-1.35.tar.gz -O /tmp/tar-1.35.tar.gz \
    && tar -xzf /tmp/tar-1.35.tar.gz -C /tmp \
    && cd /tmp/tar-1.35 \
    && ./configure FORCE_UNSAFE_CONFIGURE=1 --prefix=/usr \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/tar-1.35*

# Set locale
RUN env LANG=en_US.UTF-8 locale-gen --purge en_US.UTF-8 \
    && printf 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale


VOLUME /src
VOLUME /work

WORKDIR /work
