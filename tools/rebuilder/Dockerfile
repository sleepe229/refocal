# Refocal Android rebuilder: pinned toolchain for reproducible release builds (S8, COMP-FDR-004).
# Mirrors what the F-Droid build server does: Debian, OpenJDK, Android SDK from Google,
# Flutter from the repo's git submodule, then apksigcopier/diffoscope for verification.
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file openjdk-21-jdk-headless \
      python3 apksigcopier diffoscope-minimal ccache \
    && rm -rf /var/lib/apt/lists/*

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ARG CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG CMDLINE_TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60
RUN curl -fsSL -o /tmp/clt.zip https://dl.google.com/android/repository/${CMDLINE_TOOLS} \
    && echo "${CMDLINE_TOOLS_SHA1}  /tmp/clt.zip" | sha1sum -c - \
    && mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && unzip -q /tmp/clt.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/clt.zip
# sdkmanager verifies each package against the checksum in Google's repository XML.
RUN yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null \
    && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --install \
         "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.31.6" \
         "platform-tools" >/dev/null \
    && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --list_installed \
    && chmod -R a+rX ${ANDROID_HOME}  # sdkmanager unpacks executables as rwxr--r--

ENV PATH=${ANDROID_HOME}/build-tools/36.0.0:${PATH}
# Unprivileged builder; UID/GID are build args so bind mounts stay writable.
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} builder && useradd -m -u ${UID} -g ${GID} builder
USER builder
WORKDIR /home/builder
