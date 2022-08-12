# Help
# Setup container:
##      docker build -t androidsystemwebviewbuilder:v1 --build-arg CHROMIUM_VERSION="1.2.3.4" .
# Chromium version:
##      git checkout -b stable_77 tags/77.0.3865.90 ; gclient sync --with_branch_heads --nohooks --job 16
##      Or:
##      gclient sync --with_branch_heads -r 74.0.3729.186

ARG UBUNTU=20.04
ARG RISK=edge

FROM ubuntu:$UBUNTU as builder

MAINTAINER NiKo Zhong "aug3073911@gmail.com"

# Snap: Grab dependencies
RUN apt-get update && \
    apt-get install --yes \
        curl \
        jq \
        squashfs-tools

# Grab the core snap (for backwards compatibility) from the stable channel and
# unpack it in the proper place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core' | jq '.download_url' -r) --output core.snap && \
        mkdir -p /snap/core && \
        unsquashfs -d /snap/core/current core.snap

# Grab the core18 snap (which snapcraft uses as a base) from the stable channel
# and unpack it in the proper place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core18' | jq '.download_url' -r) --output core18.snap && \
        mkdir -p /snap/core18 && \
        unsquashfs -d /snap/core18/current core18.snap

# Grab the core20 snap (which snapcraft uses as a base) from the stable channel
# and unpack it in the proper place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core20' | jq '.download_url' -r) --output core20.snap && \
        mkdir -p /snap/core20 && \
        unsquashfs -d /snap/core20/current core20.snap

# Grab the snapcraft snap from the $RISK channel and unpack it in the proper
# place.
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/snapcraft?channel='$RISK | jq '.download_url' -r) --output snapcraft.snap && \
        mkdir -p /snap/snapcraft && \
        unsquashfs -d /snap/snapcraft/current snapcraft.snap

# Fix Python3 installation: Make sure we use the interpreter from
# the snapcraft snap:
RUN unlink /snap/snapcraft/current/usr/bin/python3 && \
        ln -s /snap/snapcraft/current/usr/bin/python3.* /snap/snapcraft/current/usr/bin/python3 && \
        echo /snap/snapcraft/current/lib/python3.*/site-packages >> /snap/snapcraft/current/usr/lib/python3/dist-packages/site-packages.pth

# Create a snapcraft runner (TODO: move version detection to the core of
# snapcraft).
RUN mkdir -p /snap/bin && \
        echo "#!/bin/sh" > /snap/bin/snapcraft && \
        snap_version="$(awk '/^version:/{print $2}' /snap/snapcraft/current/meta/snap.yaml | tr -d \')" && echo "export SNAP_VERSION=\"$snap_version\"" >> /snap/bin/snapcraft && \
        echo 'exec "$SNAP/usr/bin/python3" "$SNAP/bin/snapcraft" "$@"' >> /snap/bin/snapcraft && \
        chmod +x /snap/bin/snapcraft

# Multi-stage build, only need the snaps from the builder. Copy them one at a
# time so they can be cached.
FROM ubuntu:$UBUNTU as snap
COPY --from=builder /snap/core /snap/core
COPY --from=builder /snap/core18 /snap/core18
COPY --from=builder /snap/core20 /snap/core20
COPY --from=builder /snap/snapcraft /snap/snapcraft
COPY --from=builder /snap/bin/snapcraft /snap/bin/snapcraft

# Generate locale and install dependencies.
RUN apt-get update && \
    apt-get install --yes snapd sudo locales && \
    locale-gen en_US.UTF-8

# Set the proper environment.
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENV PATH="/snap/bin:/snap/snapcraft/current/usr/bin:$PATH"
ENV SNAP="/snap/snapcraft/current"
ENV SNAP_NAME="snapcraft"
ENV SNAP_ARCH="amd64"

# FROM ubuntu:$UBUNTU as chromium

ARG CHROMIUM_VERSION
ARG DEBIAN_FRONTEND=noninteractive

RUN if test -z $CHROMIUM_VERSION ;then \
        echo "Not specified CHROMIUM_VERSION" ;fi
RUN echo "Source version: $CHROMIUM_VERSION"

# Dependencies
RUN echo "deb http://archive.ubuntu.com/ubuntu trusty multiverse" >> /etc/apt/sources.list
RUN apt-get update && \
    apt-get install -qy \
        git \
        build-essential \
        clang \
        curl \
        lsb-release \
        sudo \
        fuse \
        snapd \
        snap-confine \
        squashfuse \
        init \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
# RUN curl -L https://src.chromium.org/chrome/trunk/src/build/install-build-deps.sh > /tmp/install-build-deps.sh
# RUN chmod +x /tmp/install-build-deps.sh
# RUN /tmp/install-build-deps.sh --no-prompt --no-arm --no-chromeos-fonts --no-nacl
# RUN rm /tmp/install-build-deps.sh

# User and working dir
ENV USERNAME chromium_builder
RUN useradd -m $USERNAME && echo "$USERNAME":"$USERNAME" | chpasswd && adduser $USERNAME sudo
USER $USERNAME
ENV HOME /home/$USERNAME
WORKDIR $HOME

# depot_tools
ENV DEPOT_TOOLS /home/$USERNAME/depot_tools
ENV PATH $PATH:$DEPOT_TOOLS
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DEPOT_TOOLS
RUN echo -e "\n# Add Chromium's depot_tools to the PATH." >> .bashrc
RUN echo "export PATH=\"\$PATH:$DEPOT_TOOLS\"" >> .bashrc

# Source code
ENV SOURCE_PATH $HOME/chromium
RUN mkdir $SOURCE_PATH
WORKDIR $SOURCE_PATH
RUN fetch --no-history --nohooks android

# Dependencies and gclient hooks
WORKDIR $SOURCE_PATH/src
RUN gclient sync

# Specified chromium version
RUN if [ ! -n "$CHROMIUM_VERSION" ]; then \
        git fetch origin $CHROMIUM_VERSION ; \
        git checkout -b $CHROMIUM_VERSION FETCH_HEAD ; \
        gclient sync --with_branch_heads -D ; \
    fi

WORKDIR $SOURCE_PATH/src
USER root
RUN build/install-build-deps.sh
RUN build/install-build-deps-android.sh
USER $USERNAME
RUN gclient runhooks

# Build
# gn gen out/Release --args='target_os="android" is_debug=false is_official_build=true enable_nacl=false is_chrome_branded=false use_official_google_api_keys=false enable_resource_whitelist_generation=true ffmpeg_branding="Chrome" proprietary_codecs=true enable_remoting=true'
RUN echo -e "Build Chromium with Ninja using the command:"
RUN echo -e "autoninja -C out/Default chrome_public_apk -j54"
RUN echo -e "Build Android system webview(L+/21+) with Ninja using the command:"
RUN echo -e "autoninja -C out/Default system_webview_apk -j54"
RUN echo -e "Q+/29+:"
RUN echo -e "autoninja -C out/Default trichrome_webview_apk -j54"

# Container
USER $USERNAME
CMD /bin/bash

