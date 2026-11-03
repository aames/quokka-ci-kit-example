@@@ name
Node
@@@ args
ARG NODE_VERSION=@@VERSION@@
ARG NODE_SHA256_AMD64=@@SHA256_AMD64@@
ARG NODE_SHA256_ARM64=@@SHA256_ARM64@@
@@@ check
nvmrc="$(tr -d '[:space:]' < /pins/@@PIN_BASE@@)"
[ "${nvmrc#v}" = "$NODE_VERSION" ] || { echo "@@PIN_FILE@@ pins ${nvmrc:-nothing}, this file ${NODE_VERSION}" >&2; exit 1; }
@@@ amd64
node_arch=x64; node_sha="$NODE_SHA256_AMD64"
@@@ arm64
node_arch=arm64; node_sha="$NODE_SHA256_ARM64"
@@@ fetch
curl -fsSL --retry 3 -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
echo "${node_sha}  /tmp/node.tar.xz" | sha256sum -c --quiet -
mkdir /usr/local/node
tar -xJf /tmp/node.tar.xz -C /usr/local/node --strip-components=1 --no-same-owner
@@@ tmp
/tmp/node.tar.xz
@@@ dirs
/home/ci/.npm
@@@ path
/usr/local/node/bin
@@@ env-comment
@@@ env
npm_config_cache=/home/ci/.npm
npm_config_update_notifier=false
