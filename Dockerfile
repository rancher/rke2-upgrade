ARG ALPINE=alpine:3.23
FROM ${ALPINE} AS verify
ARG TARGETARCH
ARG TAG
WORKDIR /verify

# Copy the pre-downloaded files from the local directory (those files are retrieved by scripts/download)
COPY artifacts/sha256sum-${TARGETARCH}.txt .
COPY artifacts/rke2.linux-${TARGETARCH}.tar.gz .

RUN apk --no-cache add file

# Verify the checksum and extract the binary
RUN set -x \
 && grep "rke2.linux-${TARGETARCH}.tar.gz" sha256sum-${TARGETARCH}.txt | sha256sum -c \
 && tar -xzf rke2.linux-${TARGETARCH}.tar.gz \
 && mv -vf bin/rke2 /opt/rke2 \
 && chmod +x /opt/rke2 \
 && file /opt/rke2

RUN set -x \
 && apk --no-cache add curl \
 && export K8S_RELEASE=$(echo ${TAG} | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+') \
 && curl -fsSLO https://dl.k8s.io/release/${K8S_RELEASE}/bin/linux/${TARGETARCH}/kubectl \
 && curl -fsSLO https://dl.k8s.io/release/${K8S_RELEASE}/bin/linux/${TARGETARCH}/kubectl.sha256 \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
 && chmod +x kubectl

FROM ${ALPINE}
ARG ARCH
ARG TAG
ARG ALPINE
LABEL org.opencontainers.image.url="https://hub.docker.com/r/rancher/rke2-upgrade"
LABEL org.opencontainers.image.source="https://github.com/rancher/rke2-upgrade"
LABEL org.opencontainers.image.base.name="${ALPINE}"
RUN apk --no-cache add \
    jq libselinux-utils bash
COPY --from=verify /opt/rke2 /opt/rke2
COPY scripts/upgrade.sh /bin/upgrade.sh
COPY scripts/semver-parse.sh /bin/semver-parse.sh
COPY --from=verify /verify/kubectl /usr/local/bin/kubectl
ENTRYPOINT ["/bin/upgrade.sh"]
CMD ["upgrade"]
