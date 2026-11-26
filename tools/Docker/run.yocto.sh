#!/usr/bin/env bash

# Hardcoded UID and GID for jenkins (126:127)
JENKINS_UID=126
JENKINS_GID=127

# Run container as the host's 'jenkins' user
docker run -it \
  --rm \
  -u ${JENKINS_UID}:${JENKINS_GID} \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
  -v /var/lib/jenkins:/var/lib/jenkins \
  -w /var/lib/jenkins \
  -v /yocto:/yocto \
  -v /srv/http:/srv/http \
  -v /srv/tftp:/srv/tftp \
  -v /var/lib/jenkins/.config/rclone/rclone.conf:/var/lib/jenkins/.config/rclone/rclone.conf:ro \
  -v /var/lib/jenkins/Google_jsons/g-drive-uploads-x.json:/var/lib/jenkins/Google_jsons/g-drive-uploads-x.json:ro \
  Docker-image:2025.x.x