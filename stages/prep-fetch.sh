#!/bin/bash
# clones strongbox at the source branch, with its tags.
# usage: prep-fetch.sh <branch>
source /release-script/stages/lib.sh

fresh_clone https://github.com/ogri-la/strongbox strongbox "$1"
