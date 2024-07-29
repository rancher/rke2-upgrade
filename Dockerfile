ARG ALPINE=alpine:3.18
FROM ${ALPINE} AS verify
ARG TAG
WORKDIR /verify
ADD https://github.com/rancher/rke2/releases/download/${TAG}/sha256sum-${TARGETARCH}.txt .
RUN set -x \
  && apk --no-cache add \
    curl \
    file
RUN export ARTIFACT="rke2.linux-${TARGETARCH}" \
 && curl --output ${ARTIFACT}  --fail --location https://github.com/rancher/rke2/releases/download/${TAG}/${ARTIFACT} \
 && grep "rke2.linux-${TARGETARCH}$" sha256sum-${TARGETARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/rke2 \
 && chmod +x /opt/rke2 \
 && file /opt/rke2

RUN set -x \
 && apk --no-cache add curl \
 && export K8S_RELEASE=$(echo ${TAG} | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+') \
 && curl -fsSLO https://storage.googleapis.com/kubernetes-release/release/${K8S_RELEASE}/bin/linux/${TARGETARCH}/kubectl \
 && chmod +x kubectl

FROM ${ALPINE}
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
