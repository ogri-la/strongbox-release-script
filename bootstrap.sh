#!/bin/bash
# run as regular user
# called during vagrant 'provision' step
set -ex

(
    cd .ssh
    # replace the global known hosts file
    echo "github.com,192.30.252.128 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==" > known_hosts
    printf 'Host github.com\n  HostName github.com\n  IdentityFile ~/.ssh/me.pem' > config
)

export DEBIAN_FRONTEND=noninteractive # no ncurses prompts
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    git wget curl openjdk-11-jdk \
    fonts-dejavu libgtk-3-0 libxtst6 \
    docker.io \
    libxml2-utils jq

# why? arch, LetsEncrypt, expired certs, whatever
sudo apt-get install --reinstall ca-certificates

(
    cd /usr/bin
    sudo wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
    sudo chmod +x lein
)

if [ ! -d strongbox-release-script ]; then
    git clone ssh://git@github.com/ogri-la/strongbox-release-script
fi

sudo docker pull archlinux:latest
