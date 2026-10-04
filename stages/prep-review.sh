#!/bin/bash
# shows the prepared commit.
source /release-script/stages/lib.sh

git -C /work/strongbox --no-pager show --stat --patch HEAD
