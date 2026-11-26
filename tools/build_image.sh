#!/bin/bash

# ==============================================================================
# Script Name:  build_image.sh
# Description:  This script is to process building images.
# Author:       Kyle MacNeil
# ==============================================================================

# --- Safety Settings ---
# -e: Exit immediately if a command exits with a non-zero status.
# -o pipefail: Prevents errors in a pipeline from being masked.
set -eo pipefail

# --- Variables & Constants (excluding variables that use the $VERSION)---
# --- Variables common to other build scripts in the same family ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YOCTO_DIR=/yocto
LOG_FILE="${YOCTO_DIR}/build/build.log"
VERBOSE=false
SKIP_UPLOAD=false
INPUT_DIR=$YOCTO_DIR/sources/meta-x/tools/inputs
OUTPUT_DIR=$YOCTO_DIR/build/image_output
VERSIONED_CARRIERBOARD_DTSI_ABSOLUTE_PATH=$(find $INPUT_DIR -maxdepth 1 -type f -name "carrierboard*.dtsi" -print -quit)
VERSIONED_XSA_ABSOLUTE_PATH=$(find $INPUT_DIR -maxdepth 1 -type f -name "*.xsa" -print -quit)
TMP="$INPUT_DIR/tmp"
GENERIC_CARRIERBOARD_NAME="carrierboard.dtsi"
GENERIC_XSA_NAME="${VERSIONED_XSA_ABSOLUTE_PATH##*/}"
YOCTO_LOCAL_CONF_ABSOLUTE_PATH=${YOCTO_DIR}/build/conf/local.conf
SDTGEN_OUTPUT_DIR=${YOCTO_DIR}/build/generated_sdt/output
MACHINE_GEN_TOOL=${YOCTO_DIR}/sources/meta-xilinx/meta-xilinx-core/gen-machine-conf/gen-machineconf
DEPLOY_IMAGE_DIR="${YOCTO_DIR}/build/tmp/deploy/images/carrierboard/"
IMAGE_NAME=example-image
MACHINE=carrierboard
BOOT_FOLDER_NAME=MB_Boot_Files
TFTP_SRV=/srv/tftp
HTTP_SRV=/srv/http

# === SCRIPT SPECIFIC VARIABLES ===
YOCTO_BBLAYERS_CONF_ABSOLUTE_PATH=${YOCTO_DIR}/build/conf/bblayers.conf
PSU_INIT_FILE=$SDTGEN_OUTPUT_DIR/psu_init.c
CUSTOM_META_LAYER=${YOCTO_DIR}/sources/meta-layer
BRANCH=main
VERSION_MSG=""


# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Functions ---

usage() {
    cat << EOF
Usage: bash $(basename "$0") <version_number> [OPTIONS]

Required:
  <version_number>  Must be in format x.x.x (e.g., 1.0.5)

Options:
  -h, --help        Display this help message.
  -v, --verbose     Enable verbose mode.
  -t                Skip upload to TFTP and HTTP servers.
  -m <message>      Version message/notes to log with the release.
EOF
    exit 0
}

error_exit() {    
    # Always print errors to the screen (Stderr)
    echo -e "${RED}ERROR: $1${NC}" >&2
    echo -e "Check $LOG_FILE for full details." >&2
    exit 1
}

# --- Main Logic ---

main() {	
	#define variable that use $VERSION
	VERSION="$1"
	BINARIES_DIR=$OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION/Binaries/
	REV_DIR=$OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION/
	
	if [[ $EUID -eq 0 ]]; then
	   echo -e "${RED}ERROR: This script must NOT be run with sudo.${NC}"
	   echo "Bitbake will fail if root privileges are enabled for the whole script."
	   echo "However you will be prompted for the sudo password once the script begins"
	   exit 1
	fi
	
	cd $CUSTOM_META_LAYER || exit
	
	# Check for unsaved changes (tracked, untracked, modified, or deleted)
	if [ -n "$(git status --porcelain)" ]; then
		echo "Changes detected. Preparing to push..."
		
		# Stage all changes
		git add -A
		
		# Commit with a standard message
		COMMIT_MSG="automated backup: $(date '+%Y-%m-%d %H:%M:%S')"
		git commit -m "$COMMIT_MSG"
		
		# Push to the current branch
		if git push jsquared HEAD:$BRANCH; then
			echo "Successfully pushed changes!"
		else
			echo "Error: Git push failed."
			exit 1
		fi
	else
		echo "Repository is clean. No changes to push."
	fi
	
	
	echo "Version accepted: $VERSION"
	echo "------------------------"

	# Start of main logic
	
	#clean the meta-wasp folder from the previous machine gen
	git -C /yocto/sources/meta-wasp/ clean -fd
	
	#------setting up the input files and output dir ------
	echo "------setting up the input files and output dir------"
	
	mkdir -p $INPUT_DIR
	mkdir -p $OUTPUT_DIR
	
	# check if the file was found 
	if [ -z "$VERSIONED_CARRIERBOARD_DTSI_ABSOLUTE_PATH" ]; then
		echo "No file found matching the pattern."
		exit 1
	fi
	
	#copy the versioned .dtsi file into a tmp folder with a generic name to be used in build process
	rm -vrf $TMP
	mkdir -p $TMP
	cp "$VERSIONED_CARRIERBOARD_DTSI_ABSOLUTE_PATH" "$TMP/$GENERIC_CARRIERBOARD_NAME"
	
	#repeat for the xsa file
	
	# check if the file was found 
	if [ -z "$VERSIONED_XSA_ABSOLUTE_PATH" ]; then
		echo "No file found matching the pattern."
		exit 1
	fi
	
	#copy the versioned .xsa file into a tmp folder with a generic name to be used in build process
	cp "$VERSIONED_XSA_ABSOLUTE_PATH" "$TMP/$GENERIC_XSA_NAME"
	
	#------end of setting up input files ------
	
	#------start of cleaning the yocto environemnt------
	echo "------Start the cleaning of the environment------"
	
	#remove the local.conf and bblayers.conf
	if [ -f "$YOCTO_LOCAL_CONF_ABSOLUTE_PATH" ]; then
		rm -f "$YOCTO_LOCAL_CONF_ABSOLUTE_PATH"
	fi

	if [ -f "$YOCTO_BBLAYERS_CONF_ABSOLUTE_PATH" ]; then
		rm -f "$YOCTO_BBLAYERS_CONF_ABSOLUTE_PATH"
	fi
	
	#clean the build directory
	cd /yocto/build/
	
	if [ -d "/yocto/build/hw-description" ]; then
		rm -vrf hw-description
	fi

	if [ -d "/yocto/build/output" ]; then
		rm -vrf output
	fi
	
	if [ -d "/yocto/build/generated_sdt/output" ]; then
		rm -vrf generated_sdt/output
	fi
	
	#------end of cleaning the ycoto environment------
	
	#------ set up build environment -----
	cd /yocto/
	source /yocto/setupsdk build
	cd /yocto/build/
	
	#------start the sdtgen process------
	echo "------Start the sdtgen process------"
	mkdir -p $SDTGEN_OUTPUT_DIR

	source /opt/Xilinx/2025.2.1/Vitis/settings64.sh

	xsct <<EOT
sdtgen set_dt_param -dir $SDTGEN_OUTPUT_DIR
sdtgen set_dt_param -xsa $TMP/$GENERIC_XSA_NAME
sdtgen set_dt_param -include_dts $TMP/$GENERIC_CARRIERBOARD_NAME
sdtgen generate_sdt
EOT

	#patch the psu_init.c file with the "RDBI" patch
	
	RDBI_PATCH=$(cat <<-'EOF'
	/*
	 * RDBI work around code start
	*/
	//Code Omitted
	/*
	 * RDBI work around code end
	*/
EOF
)
	
	export RDBI_PATCH
	perl -i -0777 -pe 's/(unsigned long psu_ddr_phybringup_data\(void\).*?)(return 1;)/$1$ENV{RDBI_PATCH}\n\t$2/gs' "$PSU_INIT_FILE"
	
	
	#------end the sdtgen process------
	
	#------start the machine conf process in yocto------
	echo "------Start the generation of the machine conf files------"
	
	# Clean out the old read-only files first so cp doesn't try to overwrite them
	if [ -d "/yocto/sources/meta-wasp/recipes-bsp/device-tree/files" ]; then
		rm -rf /yocto/sources/meta-wasp/recipes-bsp/device-tree/files/*
	fi
	
	#copy the sdtgen ouput into the meta-wasp directory
	mkdir -p /yocto/sources/meta-wasp/recipes-bsp/device-tree/files
	cp -r ${SDTGEN_OUTPUT_DIR}/* /yocto/sources/meta-wasp/recipes-bsp/device-tree/files/
	
	#use the machine gen tool
	cd /yocto/build/
	
	$MACHINE_GEN_TOOL parse-sdt --hw-description $SDTGEN_OUTPUT_DIR -c ${YOCTO_DIR}/sources/meta-wasp/conf/ -l $YOCTO_LOCAL_CONF_ABSOLUTE_PATH --machine-name $MACHINE
	
	echo "------ Injecting Script Version $VERSION into local.conf ------"
	cat << EOF >> "$YOCTO_LOCAL_CONF_ABSOLUTE_PATH"

# Target-scoped versions to prevent breaking global recipes (like the kernel)
VERSION_ID:pn-os-release = "${VERSION}"
VERSION:pn-os-release = "${VERSION} (scarthgap)"
PRETTY_NAME:pn-os-release = "Wasp-OS v${VERSION}"
EOF
	
	#------end of the machine conf process--------
	
	#------start image build process-------
	echo "------start the image build process------"
	
	#Clean the image recipe and then start a new image build
	bitbake -c cleansstate mc:wasp-carrierboard-microblaze-pmu:device-tree mc:wasp-carrierboard-cortexa53-fsbl:device-tree device-tree $IMAGE_NAME
	
	bitbake $IMAGE_NAME
	
	#------end image build process------
	
	#------start making the image zip------
	echo "------Start packaging the Image boot files into a zip file------"
	rm -vrf $OUTPUT_DIR
	mkdir -p $OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION
	mkdir -p $OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION/Binaries
	mkdir -p $OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION/JTAG
	
	# Find the latest V file, sort them, and take the last one
	LATEST_JTAG_FLASH=$(ls $INPUT_DIR/JTAG_flash_V*.tcl | sort -V | tail -n 1)
	cp $LATEST_JTAG_FLASH $OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION/JTAG/JTAG_flash.tcl
	
	# --- Robust Binary Copies via Stable Symlinks ---
	cp -L "$DEPLOY_IMAGE_DIR/arm-trusted-firmware.elf" "$BINARIES_DIR/bl31_$VERSION.elf"
	cp -L "$DEPLOY_IMAGE_DIR/BOOT-wasp-carrierboard.bin" "$BINARIES_DIR/BOOT_$VERSION.bin"
	cp -L "$DEPLOY_IMAGE_DIR/fsbl-wasp-carrierboard.elf" "$BINARIES_DIR/fsbl_$VERSION.elf"
	cp -L "$DEPLOY_IMAGE_DIR/Image-wasp-carrierboard.bin" "$BINARIES_DIR/Image_$VERSION"
	cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.cpio.gz.u-boot" "$BINARIES_DIR/rootfs_$VERSION.cpio.gz.u-boot"
	cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.tar.gz" "$BINARIES_DIR/rootfs_$VERSION.tar.gz"
	cp -L "$DEPLOY_IMAGE_DIR/pmu-firmware-wasp-carrierboard.elf" "$BINARIES_DIR/pmufw_$VERSION.elf"
	cp -L "$DEPLOY_IMAGE_DIR/u-boot-wasp-carrierboard.elf" "$BINARIES_DIR/u-boot_$VERSION.elf"
	cp -L "$DEPLOY_IMAGE_DIR/devicetree/cortexa53-linux.dtb" "$BINARIES_DIR/system_$VERSION.dtb"
	
	# Target the rootfs .wic image directly via its generic symlink string format
	cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.wic" "$REV_DIR/wasp_image_$VERSION.wic"
	
	#compress the image rev into a zip file
	cd $REV_DIR
	zip -r ${BOOT_FOLDER_NAME}_REV$VERSION.zip .
	mv ${BOOT_FOLDER_NAME}_REV$VERSION.zip $OUTPUT_DIR
	
	#------done creating the zip folder------
	
	if [[ "$SKIP_UPLOAD" = false ]]; then
		#------Upload artifacts to the tftp server-------
		find "$TFTP_SRV" -maxdepth 1 -type f -delete

		cp -L "$DEPLOY_IMAGE_DIR/Image-wasp-carrierboard.bin" "$TFTP_SRV/Image_$VERSION"
		cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.cpio.gz.u-boot" "$TFTP_SRV/rootfs_$VERSION.cpio.gz.u-boot"
		cp -L "$DEPLOY_IMAGE_DIR/devicetree/cortexa53-linux.dtb" "$TFTP_SRV/system_$VERSION.dtb"
		cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.wic" "$TFTP_SRV/wasp_image_$VERSION.wic"

		ls $TFTP_SRV >> $TFTP_SRV/index.txt
		
		#------Finished uploading artifacts to the tftp server------
		
		#------Upload artifacts to the http server-------
		find "$HTTP_SRV" -maxdepth 1 -type f -delete

		cp -L "$DEPLOY_IMAGE_DIR/devicetree/cortexa53-linux.dtb" "$HTTP_SRV/system_$VERSION.dtb"
		cp -L "$DEPLOY_IMAGE_DIR/Image-wasp-carrierboard.bin" "$HTTP_SRV/Image_$VERSION"
		cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.cpio.gz.u-boot" "$HTTP_SRV/rootfs_$VERSION.cpio.gz.u-boot"
		cp -L "$DEPLOY_IMAGE_DIR/$IMAGE_NAME-wasp-carrierboard.rootfs.wic" "$HTTP_SRV/wasp_image_$VERSION.wic"

		ls $HTTP_SRV >> $HTTP_SRV/index.txt
		#------Finished uploading artifacts to the http server------
		
		#------Upload to G-drive-------
		rclone copy $OUTPUT_DIR/${BOOT_FOLDER_NAME}_REV$VERSION.zip "wasp-drive:06_WASP MB IMAGES/Images/Latest Experimental Release"
		
		#------Append to the revision history google sheet-------
		
		python3 - << EOF
import gspread

# Path to your existing rclone Service Account key
SERVICE_ACCOUNT_FILE = "/var/lib/jenkins/Google_jsons/g-drive-uploads-5fb0799d50b1.json"

# Spreadsheet ID of google sheet
SPREADSHEET_ID = "1Dnjmm6PPflMxIdJba934aopef0QG9uN3lersbPpvvWQ"

try:
    # Authenticate with Google Sheets API
    gc = gspread.service_account(filename=SERVICE_ACCOUNT_FILE)
    
    # Open the spreadsheet and select the first worksheet tab
    sheet = gc.open_by_key(SPREADSHEET_ID).sheet1
    
    # Define new row data
    new_row = ["$VERSION", "$VERSION_MSG"]
    
    # Append row to the bottom of the sheet
    sheet.append_row(new_row)
    print("Successfully appended build record to Google Sheet.")

except Exception as e:
    print(f"Failed to append to Google Sheet: {e}")
EOF
		
	else
		echo "Skipping upload to TFTP and HTTP servers."
	fi
	
	echo -e "${GREEN}Build completed. ${NC}See the output directory for the generated image."
}

# --- Argument Parsing ---

VERSION_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t)
            SKIP_UPLOAD=true
            shift
            ;;
        -m|--message)
            if [[ -n "$2" && "$2" != -* ]]; then
                VERSION_MSG="$2"
                shift 2
            else
                echo -e "${RED}Error: Option $1 requires a non-empty string argument.${NC}" >&2
                exit 1
            fi
            ;;
        -*)
            error_exit "Invalid option: $1"
            ;;
        *)
            if [[ -z "$VERSION_ARG" ]]; then
                VERSION_ARG="$1"
            else
                error_exit "Unexpected positional argument: $1"
            fi
            shift
            ;;
    esac
done

# Check if the required version number argument was provided
if [ -z "$VERSION_ARG" ]; then
    echo -e "${RED}Error: Missing required <version_number> argument.${NC}\n" >&2
    usage
fi

# Ensure that the version number is in proper format
if [[ ! $VERSION_ARG =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format '$VERSION_ARG'. Please use format x.x.x (e.g., 1.0.5)${NC}\n" >&2
    usage
fi

if [[ "$VERBOSE" = true ]]; then
    main "$VERSION_ARG" 2>&1 | tee "$LOG_FILE"
else
	echo "Build in progress... (Check $LOG_FILE for details)"
	main "$VERSION_ARG" > "$LOG_FILE" 2>&1
fi