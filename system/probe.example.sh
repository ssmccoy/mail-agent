#!/bin/sh
# Copy to /etc/mail-agent/probes/default, owned by root and not group-writable.
# A per-authorization /etc/mail-agent/probes/POLICY can override this script.
# This runs as the dynamic user inside the real policy cgroup and outer Landlock
# domain. Supply assertions for this host, project, harness, and mode.
set -eu

# Assert approved HTTP/2 and QUIC requests with clients that report the negotiated
# protocol. Assert TCP and UDP failures for IPv4/IPv6 unlisted external, internal,
# and loopback destinations. Research must instead pass unrestricted IP tests.
# Include the selected resolver, model service, and project build-cache service.
# Use local test receivers to prove that a timeout is an ACL denial, not a down
# destination. Test both connected and unconnected UDP, and socket rebinding.
# Invoke the installed inner profile to test read-only modes, private history,
# rw-but-not-executable caches, and denied Unix sockets/administrative interfaces.
# Exercise the native harness with a bounded fixture and verify its actual tools,
# history continuation/forks, shared login and token renewal, and subprocess exit.

# No generic endpoint or credential can establish these deployment assertions.
echo "Replace this incomplete probe with assertions for $MAIL_AGENT_SYSTEM_POLICY" >&2
exit 78
