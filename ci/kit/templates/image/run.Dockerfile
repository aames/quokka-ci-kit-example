
@@ARGS@@

USER root
COPY @@PIN_FILES@@ /pins/
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eu; \
@@CROSS_CHECKS@@
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) @@AMD64@@ ;; \
      arm64) @@ARM64@@ ;; \
      *) echo "no pinned @@TOOL_NAMES@@ for ${arch}" >&2; exit 1 ;; \
    esac; \
@@FETCH@@
@@FINISH@@

@@ENV@@
