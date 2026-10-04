# publish image: git, gh and the tools that derive and validate per-release files.
# used for fetching, deriving and every remote stage. compiles nothing.
# every build argument comes from `pins.env`. the build context is `images/`.

ARG IMAGE_UBUNTU
FROM ${IMAGE_UBUNTU}

ARG GH_VERSION
ARG GH_SHA256
ARG PARSE_CHANGELOG_VERSION
ARG PARSE_CHANGELOG_SHA256

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        appstream ca-certificates curl git jq libxml2-utils openssh-client python3 \
    && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
    && curl --silent --show-error --fail --location --output gh.tar.gz \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && echo "${GH_SHA256}  gh.tar.gz" | sha256sum --check --strict \
    && tar xzf gh.tar.gz \
    && install -m 755 "gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf gh.tar.gz "gh_${GH_VERSION}_linux_amd64"

RUN cd /tmp \
    && curl --silent --show-error --fail --location --output parse-changelog.tar.gz \
        "https://github.com/taiki-e/parse-changelog/releases/download/v${PARSE_CHANGELOG_VERSION}/parse-changelog-x86_64-unknown-linux-musl.tar.gz" \
    && echo "${PARSE_CHANGELOG_SHA256}  parse-changelog.tar.gz" | sha256sum --check --strict \
    && tar xzf parse-changelog.tar.gz \
    && install -m 755 parse-changelog /usr/local/bin/parse-changelog \
    && rm -f parse-changelog.tar.gz parse-changelog

# stages run as the host user's uid, which has no passwd entry here, and ssh refuses to run without one.
COPY common/stage-entry /usr/local/bin/stage-entry
RUN chmod 666 /etc/passwd
ENTRYPOINT ["/usr/local/bin/stage-entry"]
