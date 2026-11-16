#!/bin/bash
# Image test (no systemd needed): run inside the image as root.
#   test-image.sh <dcache version>
# Checks the RPM, the dcache account, Java, and that dcache-generator creates a
# unit per domain from a small layout (the core of the role's container mode).
set -euo pipefail
v="$1"
rpm -q "dcache-$v"
test "$(id -u dcache):$(id -g dcache)" = "994:1000"
test -f /lib/systemd/system/dcache.target
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
mkdir -p /run/tmpfiles.d /tmp/gen
/lib/systemd/system-generators/dcache-generator /tmp/gen /tmp/gen /tmp/gen
ls /tmp/gen /tmp/gen/dcache.target.wants
test -f /tmp/gen/dcache@ciZkDomain.service
test -f /tmp/gen/dcache@ciDomain.service
grep -q "BootLoader start ciDomain" /tmp/gen/dcache@ciDomain.service
echo "image test OK"
