# THE JOB IMAGE'S GENERIC LAYER, THE KIT'S (kit/README.md §2.2;
# DESIGN.md §6.0; kit/README.md §5.6, §3.2). Derived from the author's private reference implementation.
# The adopter's toolchain layer, its `image`
# Dockerfile, builds FROM this one by the build argument CIKIT_BASE.
#
# Built by ci/kit/bin/container, never by hand, from a context made of
# exactly ci/kit/image at the commit (`git archive <commit> -- ci/kit/image`),
# and tagged <project>-ci-base:<base key>, the base key being
# `kit_key <commit> base`, the hash of ci/kit/image alone (kit/README.md §3.2), so a
# toolchain pin bump never rebuilds it. Every FROM names its base by index
# digest, one digest for every architecture, so a Mac (linux/arm64) and the
# runner (linux/amd64) start from the same Debian. A digest bump is a
# reviewed edit of both FROM lines and a PATCH release with a currency row in
# the kit's CHANGELOG.md.
#
# What it holds: Debian 13 slim; the generic tools every job and the entry
# use (bash, git, make, jq, curl, openssl, perl, python3, xz, CA
# certificates, OpenSSH's client, util-linux's flock); python3 with PyYAML (the
# workflow fence imports yaml; without it the kit job's K-workflow family printed
# NOT RUN) because two of
# the kit's own fences are Python and the kit job runs in this image (kit/README.md §5.6);
# the non-root user ci, its uid and gid the build argument CIKIT_UID, which
# the launcher sets from the manifest's `user` (default 1001, the hosted
# runner's uid, so CI's cache directories stay the runner's); the entry
# script at /usr/local/bin/cikit-enter; and bash 3.2.57 at
# /opt/bash-3.2/bin/bash (the host side's proof fixture, mirroring macOS's
# /bin/bash: no verdict runs under it, so it is no pin and no currency row,
# and its version and hash are the two build arguments below).

# --- bash 3.2.57 from the GNU source tarball ------------------------------------
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS bash32
ARG BASH32_VERSION=3.2.57
ARG BASH32_SHA256=3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev make autotools-dev bison \
 && rm -rf /var/lib/apt/lists/*
# The 2006 config.guess and config.sub know no aarch64, so the system's copies
# replace them. The y.tab.c the tarball ships predates the patches to parse.y,
# so make regenerates the parser, with bison as yacc. GCC 14 refuses K&R-era C
# by default; -fpermissive and gnu89 restore the dialect the source was
# written in, in CC itself so the build-host helpers
# (CC_FOR_BUILD) get them too. bash's own malloc is off, as every
# distribution builds it on 64-bit.
RUN set -eu; \
    curl -fsSL --retry 3 -o /tmp/bash.tar.gz "https://ftp.gnu.org/gnu/bash/bash-${BASH32_VERSION}.tar.gz"; \
    echo "${BASH32_SHA256}  /tmp/bash.tar.gz" | sha256sum -c --quiet -; \
    mkdir /tmp/bash; tar -xzf /tmp/bash.tar.gz -C /tmp/bash --strip-components=1; \
    cp /usr/share/misc/config.guess /usr/share/misc/config.sub /tmp/bash/support/; \
    cd /tmp/bash; \
    CC='gcc -std=gnu89 -fpermissive -w' CC_FOR_BUILD='gcc -std=gnu89 -fpermissive -w' CFLAGS=-O2 YACC='bison -y' \
      ./configure --prefix=/opt/bash-3.2 --without-bash-malloc --disable-nls > /dev/null; \
    make > /dev/null; \
    make install > /dev/null; \
    /opt/bash-3.2/bin/bash -c 'case "$BASH_VERSION" in 3.2.57*) ;; *) echo "built bash reports $BASH_VERSION" >&2; exit 1 ;; esac'

# --- the generic layer -----------------------------------------------------------
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git make jq curl openssl perl python3 python3-yaml xz-utils ca-certificates openssh-client util-linux \
 && rm -rf /var/lib/apt/lists/*
ARG CIKIT_UID=1001
RUN groupadd --gid "${CIKIT_UID}" ci \
 && useradd --uid "${CIKIT_UID}" --gid "${CIKIT_UID}" --create-home --shell /bin/bash ci \
 && install -d -o "${CIKIT_UID}" -g "${CIKIT_UID}" -m 0755 /src
COPY --from=bash32 /opt/bash-3.2 /opt/bash-3.2
COPY --chmod=0755 ci/kit/image/enter.sh /usr/local/bin/cikit-enter
USER ci
WORKDIR /home/ci
CMD ["bash"]
