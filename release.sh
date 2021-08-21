#!/bin/bash
# coordinates the release of ogri-la/strongbox
set -eu # everything must pass, no unbound variables
#set -x # display commands executed

export GIT_PAGER=cat

release="$1" # "1.2.3"
previous_releases=[] # populated after strongbox available

# used to check given release is greater than the previous release
if [ ! -e "semver2.sh" ]; then
    echo "downloading semver2.sh"
    curl https://raw.githubusercontent.com/Ariel-Rodriguez/sh-semversion-2/1.0.3/semver2.sh -o semver2.sh
    chmod +x semver2.sh
    echo "---"
fi


if [ ! -e "strongbox" ]; then
    echo "cloning strongbox"
    git clone ssh://git@github.com/ogri-la/strongbox
    echo "---"
fi

{
    echo "cleaning strongbox"
    cd strongbox
    #git fetch # todo: disabled for speed
    git reset --hard
    git checkout develop --force
    git clean -d --force
    #lein clean # todo: disabled for speed
    echo "---"

    echo "detecting versions"
    previous_releases=$(git tag --list | grep --perl-regex '^\d+\.\d+\.\d+$' | sort --version-sort)
    readarray -t previous_releases <<< $previous_releases

    last_release=${previous_releases[-1]}
    major_release=false
    # assumes single digit releases. will work until we hit double digits.
    if [ ${release:0:1} -gt ${last_release:0:1} ]; then
        major_release=true
    fi

    #echo "previous releases: $previous_releases"
    #echo "last release: $last_release"
    #echo "this release: $release"

    rc=$(../semver2.sh "$release" "$last_release")
    if [ "$rc" = -1 ]; then
        echo "FAILED: given release ('$release') is *less than* the last release ('$last_release')"
        exit 1
    fi
    if [ "$rc" = 0 ]; then
        echo "FAILED: given release ('$release') is *equal to* the last release ('$last_release')"
        exit 1
    fi

    major_version=${release:0:1} # '5' in '5.6.7'
    echo "last release: $last_release"
    echo "this release: $release"
    echo "---"

    echo "creating release branch '$release'"
    # if branch exists, delete it.
    if [ ! -z $(git --no-pager branch | grep "$release") ]; then
        git branch "$release" --delete --force
    fi
    git checkout -b "$release"
    echo "---"

    echo "updating project.clj"
    sed --regexp-extended \
        --in-place \
        "s/defproject ogri-la\/strongbox \"[0-9.]+-unreleased\"/defproject ogri-la\/strongbox \"$release\"/" \
        project.clj
    echo "---"
    
    if $major_release; then
        echo "updating SECURITY.md"
        grep "| $major_version.x.x" SECURITY.md || {
            sed --in-place 's/:heavy_minus_sign:/:x:               /' SECURITY.md
            sed --in-place 's/:heavy_check_mark:/:heavy_minus_sign:/' SECURITY.md
            
            new_section="| $major_version.x.x   | :heavy_check_mark: |"
            sed --regexp-extended \
                --in-place \
                "/\- \|$/a $new_section" \
                SECURITY.md
        }
        echo "---"
    fi
    
    grep "## $release" CHANGELOG.md || {
        echo "update CHANGELOG.md"
        
        
        echo "---"
    }
    
    
}
