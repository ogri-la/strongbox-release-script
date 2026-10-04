#!/bin/bash
# checks the GitHub token works, has the `repo` scope and can push to each given repository.
# usage: token-check.sh <owner/repo>...
source /release-script/stages/lib.sh

remedy='hint="issue a new classic token with the repo scope at https://github.com/settings/tokens and write it to .github-token"'

[ -n "${GITHUB_TOKEN:-}" ] || die "no GitHub token was given to this stage"

response=$(gh api --include user 2>&1) || {
    if grep --quiet 'HTTP 401' <<< "$response"; then
        die "GitHub rejected the token (HTTP 401); it may have been revoked, GitHub revokes tokens it considers stale or exposed" "$remedy"
    fi
    die "could not reach the GitHub API to check the token" "detail=\"$(tail -1 <<< "$response")\""
}

scopes=$(grep --ignore-case '^x-oauth-scopes:' <<< "$response" | cut -d: -f2- | tr -d ' \r')
if ! tr ',' '\n' <<< "$scopes" | grep --quiet --line-regexp 'repo'; then
    die "the token lacks the repo scope" "found=\"${scopes:-none}\"" "required=repo" "$remedy"
fi

login=$(sed -n '/^{/,$p' <<< "$response" | jq -r .login)
for repo in "$@"; do
    push=$(gh api "repos/$repo" --jq .permissions.push 2>/dev/null) || die "cannot read repository with this token" "repo=$repo"
    [ "$push" = true ] || die "the token's account cannot push to this repository" "repo=$repo" "account=$login"
done

log INFO "GitHub token verified" "account=$login" "scopes=$scopes" "repositories=$#"
