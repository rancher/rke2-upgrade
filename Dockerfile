ARG ALPINE=alpine:3.18
FROM ${ALPINE} AS verify
ARG ARCH
ARG TAG
WORKDIR /verify
ADD https://github.com/rancher/rke2/releases/download/${TAG}/sha256sum-${ARCH}.txt .
RUN set -x \
  && apk --no-cache add \
    curl \
    file
RUN export ARTIFACT="rke2.linux-${ARCH}" \
 && curl --output ${ARTIFACT}  --fail --location https://github.com/rancher/rke2/releases/download/${TAG}/${ARTIFACT} \
 && grep "rke2.linux-${ARCH}$" sha256sum-${ARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/rke2 \
 && chmod +x /opt/rke2 \
 && file /opt/rke2

RUN set -x \
 && apk --no-cache add curl \
 && export K8S_RELEASE=$(echo ${TAG} | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+') \
 && curl -fsSLO https://cdn.dl.k8s.io/release/${K8S_RELEASE}/bin/linux/${ARCH}/kubectl \
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
