@@@ name
Python
@@@ args
# Python's Linux builds come from python-build-standalone
# (https://github.com/astral-sh/python-build-standalone), release PBS_TAG,
# each checksum from that release's SHA256SUMS file: CPython publishes no
# Linux binary of its own.
ARG PYTHON_VERSION=@@VERSION@@
ARG PBS_TAG=@@PBS_TAG@@
ARG PYTHON_SHA256_AMD64=@@SHA256_AMD64@@
ARG PYTHON_SHA256_ARM64=@@SHA256_ARM64@@
@@@ check
pyver="$(tr -d '[:space:]' < /pins/@@PIN_BASE@@)"
[ "$pyver" = "$PYTHON_VERSION" ] || { echo "@@PIN_FILE@@ pins ${pyver:-nothing}, this file ${PYTHON_VERSION}" >&2; exit 1; }
@@@ amd64
py_arch=x86_64; py_sha="$PYTHON_SHA256_AMD64"
@@@ arm64
py_arch=aarch64; py_sha="$PYTHON_SHA256_ARM64"
@@@ fetch
curl -fsSL --retry 3 -o /tmp/python.tar.gz "https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/cpython-${PYTHON_VERSION}+${PBS_TAG}-${py_arch}-unknown-linux-gnu-install_only_stripped.tar.gz"
echo "${py_sha}  /tmp/python.tar.gz" | sha256sum -c --quiet -
tar -xzf /tmp/python.tar.gz -C /usr/local
@@@ tmp
/tmp/python.tar.gz
@@@ dirs
@@@ path
/usr/local/python/bin
@@@ env-comment
@@@ env
PIP_DISABLE_PIP_VERSION_CHECK=1
PYTHONDONTWRITEBYTECODE=1
