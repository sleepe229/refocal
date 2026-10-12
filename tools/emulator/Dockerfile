# Headless Android emulator for end-to-end checks without a phone (AOSP image, no GMS — same
# as the nightly Patrol matrix in 10-testing-qa). Needs /dev/kvm: docker run --device /dev/kvm.
FROM refocal-rebuilder:s8
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpulse0 libnss3 libxcomposite1 libxcursor1 libxdamage1 libxi6 libxtst6 libxrandr2 \
      libasound2t64 libgl1 libegl1 libdrm2 libgbm1 libxkbfile1 libbsd0 libtinfo6 \
    && rm -rf /var/lib/apt/lists/*
RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --install "emulator" \
      "system-images;android-35;default;x86_64" >/dev/null \
    && chmod -R a+rX ${ANDROID_HOME}
ENV PATH=${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}
USER builder
RUN echo no | ${ANDROID_HOME}/cmdline-tools/latest/bin/avdmanager create avd -n refocal35 -k "system-images;android-35;default;x86_64" -d pixel_6 >/dev/null
