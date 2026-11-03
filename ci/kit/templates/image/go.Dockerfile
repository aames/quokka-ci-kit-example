@@@ name
Go
@@@ args
ARG GO_VERSION=@@VERSION@@
ARG GO_SHA256_AMD64=@@SHA256_AMD64@@
ARG GO_SHA256_ARM64=@@SHA256_ARM64@@
@@@ check
toolchain="$(awk '$1 == "toolchain" { print $2; exit }' /pins/@@PIN_BASE@@)"
[ "$toolchain" = "go${GO_VERSION}" ] || { echo "@@PIN_FILE@@ pins ${toolchain:-no toolchain}, this file go${GO_VERSION}" >&2; exit 1; }
@@@ amd64
go_sha="$GO_SHA256_AMD64"
@@@ arm64
go_sha="$GO_SHA256_ARM64"
@@@ fetch
curl -fsSL --retry 3 -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz"
echo "${go_sha}  /tmp/go.tar.gz" | sha256sum -c --quiet -
tar -xzf /tmp/go.tar.gz -C /usr/local
@@@ tmp
/tmp/go.tar.gz
@@@ dirs
/home/ci/go /home/ci/go/pkg /home/ci/go/pkg/mod /home/ci/.cache /home/ci/.cache/go-build
@@@ path
/usr/local/go/bin
@@@ env-comment
# GOTOOLCHAIN=local: Go never downloads another toolchain inside a job.
# CGO_ENABLED=0: the image carries no C compiler and the service needs none.
@@@ env
GOTOOLCHAIN=local
CGO_ENABLED=0
GOPATH=/home/ci/go
GOCACHE=/home/ci/.cache/go-build
