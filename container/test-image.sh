#!/bin/bash
# Image test: run inside the image as root (entrypoint overridden).
#   test-image.sh <dcache version>
# Checks the RPM, the dcache account, Java, the generator, and that the
# entrypoint resolves a domain of a small layout to its java command.
set -euo pipefail
v="$1"
rpm -q "dcache-$v"
test "$(id -u dcache):$(id -g dcache)" = "994:1000"
command -v setpriv
java -version 2>&1 | head -1
cat > /etc/dcache/dcache.conf <<'CONF'
dcache.layout=citest
CONF
cat > /etc/dcache/layouts/citest.conf <<'LAYOUT'
[ciZkDomain]
[ciZkDomain/zookeeper]
[ciDomain]
[ciDomain/topo]
LAYOUT
out="$(DCACHE_DOMAIN_DRYRUN=1 /usr/local/bin/dcache-domain ciDomain)"
echo "$out"
echo "$out" | grep -q "^user=dcache "
echo "$out" | grep -q "BootLoader start ciDomain"
if /usr/local/bin/dcache-domain noSuchDomain 2>/dev/null; then
    echo "unknown domain must fail" >&2; exit 1
fi
echo "image test OK"
