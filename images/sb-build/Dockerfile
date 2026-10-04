# build image: Temurin 17 JDK, leiningen, appimagetool and the tools to inspect shared objects.
# no credentials are ever given to containers of this image.
# every build argument comes from `pins.env`. the build context is `images/`.

ARG IMAGE_TEMURIN
FROM ${IMAGE_TEMURIN}

ARG TEMURIN_VERSION
ARG LEIN_VERSION
ARG LEIN_SCRIPT_SHA256
ARG LEIN_JAR_SHA256
ARG APPIMAGETOOL_VERSION
ARG APPIMAGETOOL_SHA256
ARG APPIMAGE_RUNTIME_VERSION
ARG APPIMAGE_RUNTIME_SHA256

# fonts, GTK and OpenGL: compiling strongbox initialises JavaFX, which loads its native libraries,
# including its OpenGL pipeline (`prism_es2`, which needs libGL and libXxf86vm).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        binutils ca-certificates file git python3 unzip wget \
        fonts-dejavu libgtk-3-0t64 libxtst6 libgl1 libxxf86vm1 \
    && rm -rf /var/lib/apt/lists/*

# the base image's JDK must be the pinned one.
RUN grep --quiet --fixed-strings "JAVA_RUNTIME_VERSION=\"${TEMURIN_VERSION}\"" "$JAVA_HOME/release"

# leiningen, with its jar installed up front so it never self-installs.
RUN wget --quiet --output-document /usr/local/bin/lein \
        "https://raw.githubusercontent.com/technomancy/leiningen/${LEIN_VERSION}/bin/lein" \
    && echo "${LEIN_SCRIPT_SHA256}  /usr/local/bin/lein" | sha256sum --check --strict \
    && chmod 755 /usr/local/bin/lein \
    && mkdir -p /opt/lein \
    && wget --quiet --output-document "/opt/lein/leiningen-${LEIN_VERSION}-standalone.jar" \
        "https://github.com/technomancy/leiningen/releases/download/${LEIN_VERSION}/leiningen-${LEIN_VERSION}-standalone.jar" \
    && echo "${LEIN_JAR_SHA256}  /opt/lein/leiningen-${LEIN_VERSION}-standalone.jar" | sha256sum --check --strict
ENV LEIN_JAR=/opt/lein/leiningen-${LEIN_VERSION}-standalone.jar

# appimagetool, extracted so it runs without FUSE, and the runtime it embeds in AppImages.
RUN cd /opt \
    && wget --quiet --output-document appimagetool.AppImage \
        "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage" \
    && echo "${APPIMAGETOOL_SHA256}  appimagetool.AppImage" | sha256sum --check --strict \
    && chmod 755 appimagetool.AppImage \
    && ./appimagetool.AppImage --appimage-extract > /dev/null \
    && mv squashfs-root /opt/appimagetool \
    && rm appimagetool.AppImage \
    && wget --quiet --output-document /opt/appimage-runtime \
        "https://github.com/AppImage/type2-runtime/releases/download/${APPIMAGE_RUNTIME_VERSION}/runtime-x86_64" \
    && echo "${APPIMAGE_RUNTIME_SHA256}  /opt/appimage-runtime" | sha256sum --check --strict
COPY sb-build/appimagetool /usr/local/bin/appimagetool

# stages run as the host user's uid, which has no passwd entry here. without one, java sets `user.home` to '?'
# and JavaFX extracts its native libraries into a directory named '?' in the working directory.
COPY common/stage-entry /usr/local/bin/stage-entry
RUN chmod 666 /etc/passwd
ENTRYPOINT ["/usr/local/bin/stage-entry"]
