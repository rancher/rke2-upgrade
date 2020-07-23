ARG ALPINE=alpine:3.11
FROM ${ALPINE} AS verify
ARG ARCH
ARG TAG
WORKDIR /verify
ADD https://github.com/rancher/rke2/releases/download/${TAG}/sha256sum-${ARCH}.txt .
RUN set -x \
 && apk --no-cache add \
    curl \
    file
RUN export ARTIFACT="rke2.linux-amd64" \
 && curl --output ${ARTIFACT}  --fail --location https://github.com/rancher/rke2/releases/download/${TAG}/${ARTIFACT} \
 && grep -E " rke2.*" sha256sum-${ARCH}.txt | sha256sum -c \
 && mv -vf ${ARTIFACT} /opt/rke2 \
 && chmod +x /opt/rke2 \
 && file /opt/rke2

FROM ${ALPINE}
ARG ARCH
ARG TAG
RUN apk --no-cache add \
    jq
COPY --from=verify /opt/rke2 /opt/rke2
COPY scripts/upgrade.sh /bin/upgrade.sh
ENTRYPOINT ["/bin/upgrade.sh"]
CMD ["upgrade"]
