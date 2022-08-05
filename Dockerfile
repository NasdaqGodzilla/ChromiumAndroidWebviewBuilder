# Help
# Setup container:
##      docker build -t androidsystemwebviewbuilder:v1 --build-arg CHROMIUM_VERSION="1.2.3.4" .
# Chromium version:
##      git checkout -b stable_77 tags/77.0.3865.90 ; gclient sync --with_branch_heads --nohooks --job 16
##      Or:
##      gclient sync --with_branch_heads -r 74.0.3729.186

FROM ubuntu:20.04
MAINTAINER NiKo Zhong "aug3073911@gmail.com"

ARG CHROMIUM_VERSION

RUN if test -z $CHROMIUM_VERSION ;then \
        echo "Not specified CHROMIUM_VERSION" ;fi
RUN echo "Source version: $CHROMIUM_VERSION"

# Dependencies
RUN echo "deb http://archive.ubuntu.com/ubuntu trusty multiverse" >> /etc/apt/sources.list
RUN apt-get update && apt-get install -qy git build-essential clang curl
# RUN curl -L https://src.chromium.org/chrome/trunk/src/build/install-build-deps.sh > /tmp/install-build-deps.sh
# RUN chmod +x /tmp/install-build-deps.sh
# RUN /tmp/install-build-deps.sh --no-prompt --no-arm --no-chromeos-fonts --no-nacl
# RUN rm /tmp/install-build-deps.sh

# User and working dir
ENV USERNAME chromium_builder
RUN useradd -m $USERNAME
USER $USERNAME
ENV HOME /home/$USERNAME
WORKDIR $HOME

# depot_tools
ENV DEPOT_TOOLS /home/$USERNAME/depot_tools
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DEPOT_TOOLS
ENV PATH $PATH:$DEPOT_TOOLS
RUN echo -e "\n# Add Chromium's depot_tools to the PATH." >> .bashrc
RUN echo "export PATH=\"\$PATH:$DEPOT_TOOLS\"" >> .bashrc

# Source code
ENV SOURCE_PATH $HOME/chromium
RUN mkdir $SOURCE_PATH
WORKDIR $SOURCE_PATH
RUN fetch --nohooks android

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
RUN build/install-build-deps.sh
RUN build/install-build-deps-android.sh
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

