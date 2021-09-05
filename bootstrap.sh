#!/bin/bash
# run as regular user
# called during vagrant 'provision' step
set -ex

(
    cd .ssh
    touch known_hosts
    ssh-keygen -R github.com  # removes any existing github keys
    printf 'Host github.com\n  HostName github.com\n  IdentityFile ~/.ssh/me.pem' > config
)

# append this to the global known hosts file
echo "github.com,192.30.252.128 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==" > ~/.ssh/known_hosts

export DEBIAN_FRONTEND=noninteractive # no ncurses prompts
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    git wget curl openjdk-11-jdk-headless \
    fonts-dejavu libgtk-3-0 libxtst6

if [ ! -d strongbox-release-script ]; then
    git clone ssh://git@github.com/ogri-la/strongbox-release-script
fi
