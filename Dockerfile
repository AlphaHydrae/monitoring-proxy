FROM nginx:1.29.0-alpine

# Note: this image uses https://github.com/just-containers/s6-overlay to start
# and supervise both nginx and an OpenSSH server in the container.
#
# See
# https://github.com/just-containers/s6-overlay?tab=readme-ov-file#customizing-s6-overlay-behaviour
# for documentation on how the following variables customize the behavior of
# s6-overlay.
ENV S6_OVERLAY_VERSION=3.2.1.0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2

USER root

RUN apk add --no-cache --virtual setup-dependencies ca-certificates wget && \
    wget -qO /tmp/s6-overlay-noarch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz && \
    wget -qO /tmp/s6-overlay-x86_64.tar.xz https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-x86_64.tar.xz && \
    apk add --no-cache openssh-server tzdata && \
    apk del setup-dependencies && \
    rm -rf /tmp/* && \
    addgroup -S monitoring && \
    adduser -G monitoring -S -s /sbin/nologin monitoring && \
    echo "monitoring:*" | chpasswd -e && \
    mkdir /home/monitoring/.ssh && \
    touch /home/monitoring/.ssh/authorized_keys && \
    chown -R monitoring:monitoring /home/monitoring && \
    chmod 700 /home/monitoring /home/monitoring/.ssh && \
    chmod 600 /home/monitoring/.ssh/authorized_keys

COPY /fs/ /

ENTRYPOINT ["/init"]
CMD ["nginx", "-g", "daemon off;"]
