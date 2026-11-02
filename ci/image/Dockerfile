# The job image's toolchain layer: Go and Node on the kit's base.
#
# ci/kit/bin/container builds this, never a person, from a context of exactly
# the manifest's image-path list at the commit under test (ci/image,
# api/go.mod, web/.nvmrc), FROM the kit's base image by the build argument
# CIKIT_BASE, and labels it with its key itself. It is built on each machine
# for that machine's own architecture and never pulled.
#
# The pins live where the tools read them: Go in api/go.mod's toolchain line,
# Node in web/.nvmrc. This file names the same versions with each release
# tarball's sha256, and the build stops if the two disagree, so a pin bump is
# one reviewed edit of the pin file and this file together.

ARG CIKIT_BASE
FROM ${CIKIT_BASE}

ARG GO_VERSION=1.27.3
ARG GO_SHA256_AMD64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG GO_SHA256_ARM64=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49
ARG NODE_VERSION=24.22.1
ARG NODE_SHA256_AMD64=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
ARG NODE_SHA256_ARM64=dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e

USER root
COPY api/go.mod web/.nvmrc /pins/
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eu; \
    toolchain="$(awk '$1 == "toolchain" { print $2; exit }' /pins/go.mod)"; \
    [ "$toolchain" = "go${GO_VERSION}" ] || { echo "api/go.mod pins ${toolchain:-no toolchain}, this file go${GO_VERSION}" >&2; exit 1; }; \
    nvmrc="$(tr -d '[:space:]' < /pins/.nvmrc)"; \
    [ "${nvmrc#v}" = "$NODE_VERSION" ] || { echo "web/.nvmrc pins ${nvmrc:-nothing}, this file ${NODE_VERSION}" >&2; exit 1; }; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) go_sha="$GO_SHA256_AMD64"; node_arch=x64; node_sha="$NODE_SHA256_AMD64" ;; \
      arm64) go_sha="$GO_SHA256_ARM64"; node_arch=arm64; node_sha="$NODE_SHA256_ARM64" ;; \
      *) echo "no pinned Go or Node for ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz"; \
    echo "${go_sha}  /tmp/go.tar.gz" | sha256sum -c --quiet -; \
    tar -xzf /tmp/go.tar.gz -C /usr/local; \
    curl -fsSL --retry 3 -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    echo "${node_sha}  /tmp/node.tar.xz" | sha256sum -c --quiet -; \
    mkdir /usr/local/node; \
    tar -xJf /tmp/node.tar.xz -C /usr/local/node --strip-components=1 --no-same-owner; \
    rm -rf /tmp/go.tar.gz /tmp/node.tar.xz /pins; \
    install -d -o ci -g ci /home/ci/go /home/ci/go/pkg /home/ci/go/pkg/mod /home/ci/.cache /home/ci/.cache/go-build /home/ci/.npm

# GOTOOLCHAIN=local: Go never downloads another toolchain inside a job.
# CGO_ENABLED=0: the image carries no C compiler and the service needs none.
ENV PATH=/usr/local/go/bin:/usr/local/node/bin:/usr/local/bin:/usr/bin:/bin \
    GOTOOLCHAIN=local \
    CGO_ENABLED=0 \
    GOPATH=/home/ci/go \
    GOCACHE=/home/ci/.cache/go-build \
    npm_config_cache=/home/ci/.npm \
    npm_config_update_notifier=false
USER ci
WORKDIR /home/ci
