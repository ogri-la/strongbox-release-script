#!/bin/bash
# prepares a release of ogri-la/strongbox
# assumes no outstanding changes or previous attempts!
# run as a regular user in Vagrant
# this script:
# * does a clean checkout of strongbox `develop` branch
# * creates a release branch
# * updates README, SECURITY, CHANGELOG, pom.xml
# * creates a pull request against master with a checklist
set -eu # everything must pass, no unbound variables
#set -x # display commands executed

export GIT_PAGER=cat
GITHUB_TOKEN=$(cat .github-token)
export GITHUB_TOKEN

release="$1" # "1.2.3"
previous_releases=[] # populated after strongbox available

# the branch to build a release from (develop)
branch=${2:-develop}

if [ ! -e "semver2.sh" ]; then
    echo "--- downloading semver2.sh ---"
    curl https://raw.githubusercontent.com/Ariel-Rodriguez/sh-semversion-2/1.0.3/semver2.sh -o semver2.sh
    chmod +x semver2.sh
    echo
fi

if [ ! -e "gh" ]; then
    echo "--- downloading Github's 'gh' tool ---"
    rm -rf gh_1.14.0_linux_amd64/ gh_1.14.0_linux_amd64.tar.gz gh.tar.gz
    wget https://github.com/cli/cli/releases/download/v1.14.0/gh_1.14.0_linux_amd64.tar.gz --output-document gh.tar.gz
    tar xvzf gh.tar.gz
    mv gh_1.14.0_linux_amd64/bin/gh ./gh
    rm -rf gh_1.14.0_linux_amd64
    echo
fi

if [ ! -e "strongbox" ]; then
    echo "--- cloning strongbox ---"
    git clone ssh://git@github.com/ogri-la/strongbox strongbox
    echo
fi

(
    cd strongbox

    echo "--- cleaning strongbox ---"
    git reset --hard
    git clean -d --force
    git fetch
    git checkout "$branch"
    git pull
    lein clean
    echo

    echo "--- detecting versions ---"
    previous_releases=$(git tag --list | grep --perl-regex '^\d+\.\d+\.\d+$' | sort --version-sort)
    readarray -t previous_releases <<< "$previous_releases"

    last_release=${previous_releases[-1]}
    major_release=false
    # assumes single digit releases. will work until we hit double digits.
    if [ "${release:0:1}" -gt "${last_release:0:1}" ]; then
        major_release=true
    fi

    rc=$(../semver2.sh "$release" "$last_release")
    if [ "$rc" = -1 ]; then
        echo "FAILED: given release ('$release') is *less than* the last release ('$last_release')"
        exit 1
    fi
    if [ "$rc" = 0 ]; then
        echo "FAILED: given release ('$release') is *equal to* the last release ('$last_release')"
        exit 1
    fi

    major_version=${release:0:1} # '4' in '4.5.6'
    echo "last release: $last_release"
    echo "this release: $release"
    echo

    echo "--- creating release branch '$release' ---"
    # if branch exists, delete it.
    if git --no-pager branch | grep --quiet "$release"; then
        git branch "$release" --delete --force
    fi
    git checkout -b "$release"
    echo

    echo "--- updating project.clj ---"
    sed --regexp-extended \
        --in-place \
        "s/defproject ogri-la\/strongbox \"[0-9.]+-unreleased\"/defproject ogri-la\/strongbox \"$release\"/" \
        project.clj
    echo

    if $major_release; then
        echo "--- updating SECURITY.md ---"
        grep "| $major_version.x.x" SECURITY.md || {
            sed --in-place 's/:heavy_minus_sign:/:x:               /' SECURITY.md
            sed --in-place 's/:heavy_check_mark:/:heavy_minus_sign:/' SECURITY.md
            
            new_section="| $major_version.x.x   | :heavy_check_mark: |"
            sed --regexp-extended \
                --in-place \
                "/\- \|$/a $new_section" \
                SECURITY.md
        }
        echo
    fi

    grep "## $release" CHANGELOG.md || {
        echo "--- updating CHANGELOG.md ---"
        new_section="$release - $(date -I)" # "4.5.6 - 2020-12-31"
        sed --in-place "0,/\[Unreleased\]/s//$new_section/" CHANGELOG.md
        echo
    }

    echo "--- updating README.md ---"
    # "strongbox-1.2.3-standalone.jar" => "strongbox-4.5.6-standalone.jar"
    sed --in-place --regexp-extended "s/strongbox-[0-9\.]+-standalone.jar/strongbox-$release-standalone.jar/g" README.md
    # "/1.2.3/" => "/4.5.6/"
    sed --in-place --regexp-extended "s/\/[0-9\.]+\//\/$release\//" README.md
    echo

    echo "--- updating pom.xml ---"
    lein pom
    echo

    echo "--- creating pull request ---"
    git commit -am "$release"
    git push --set-upstream origin "$release"
    ../gh pr create \
        --base "master" \
        --head "$release" \
        --body-file ../strongbox--pr-template.md \
        --title "$release"
    echo
)

echo "done"
