# strongbox release script

Neither Travis nor CircleCI can handle my release process so I've switched to doing it manually.

I'm sure with time and much frustration and resentment I could get these third parties to do what I wanted but I have 
more control this way.

These scripts help automate my process.

## prep.sh

Prepares a release branch of strongbox for review, updating all the bits and bobs.

## release.sh

Assumes `prep.sh` has been run. 

Tags the release on the master branch, creates a release, uploads it to Github and then updates the Arch AUR.

## post.sh

Switches back to `develop`, merges changes from master, truncates TODO, updates project file, etc etc.
