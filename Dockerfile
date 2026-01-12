FROM alpine:3.22.1 AS base
ARG TARGETARCH

FROM base AS base-amd64
ENV S6_OVERLAY_ARCH=x86_64

FROM base AS base-arm64
ENV S6_OVERLAY_ARCH=aarch64

FROM base-${TARGETARCH}${TARGETVARIANT}

ARG S6_OVERLAY_VERSION="3.2.1.0"

# Core variables
ENV PUID=1000
ENV PGID=1000
ENV TZ=UTC
ENV GENERATE_DHPARAM=true
ENV INTERVAL="0 */6 * * *"
ENV ONE_SHOT=false
ENV APPRISE_URL=
ENV NOTIFY_ON_FAILURE=false
ENV NOTIFY_ON_SUCCESS=false

# Single domain
ENV DOMAINS=
ENV EMAIL=
ENV STAGING=false

# Custom CA support
ENV CUSTOM_CA=
ENV CUSTOM_CA_SERVER=

# Different plugin support (to support Cloudflare but also normal mode)
ENV PLUGIN=standalone
ENV PROPOGATION_TIME=10
ENV CLOUDFLARE_TOKEN=

## Multi-cert support
ENV CERT_COUNT=1

#Get required packages
RUN apk update && apk add curl bash python3 py3-virtualenv procps tzdata nano shadow xz busybox-suid openssl logrotate

#Make folders
RUN mkdir /config && \
    mkdir /app && \
#Create default user
    useradd -u 1000 -U -d /config -s /bin/false mrmeeb && \
    usermod -G users mrmeeb

#Install s6-overlay
RUN curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" | tar Jpxf - -C / && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz" | tar Jpxf - -C / && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" | tar Jpxf - -C / && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz" | tar Jpxf - -C /
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 S6_VERBOSITY=1

RUN python3 -m venv /app/certbot/ && /app/certbot/bin/pip install --upgrade pip

#Get required packages for building, build, then cleanup
#Added additional pip steps to fix cython 3.0.0 issue - https://github.com/yaml/pyyaml/issues/601
COPY requirements.txt /app/certbot/requirements.txt
RUN apk add --no-cache --virtual .deps gcc python3-dev libc-dev libffi-dev && \
    /app/certbot/bin/pip install wheel setuptools && \
    /app/certbot/bin/pip install "Cython<3.0" pyyaml --no-build-isolation && \
    /app/certbot/bin/pip install -r /app/certbot/requirements.txt && \
    ln -s /app/certbot/bin/certbot /usr/bin/certbot && \
    ln -s /app/certbot/bin/apprise /usr/bin/apprise && \
    apk del .deps

COPY root /

RUN chmod +x /container-init.sh /certbot-prepare.sh /check-one-shot.sh /renew-function.sh && \
    chown -R ${PUID}:${PGID} /app /config

ENTRYPOINT [ "/init" ]

