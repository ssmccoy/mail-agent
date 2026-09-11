# Migration to system-service execution

The optional system backend, nftables policy renderer, administrative
installer, state transfer, and rollback are implemented. `make install` retains
the home executor. Keep the default `legacy` until the target host passes
qualification; the repository tests substitute the manager and confinement
commands and cannot establish kernel enforcement or native CLI compatibility.

For the remaining deployment work and completion criteria, use the [isolation
handoff checklist]. It distinguishes missing qualification probes from
implemented migration and covers the separate case of moving sessions between
machines.

For reproducible host configuration and one provisioning command per project,
use [maintained deployment tooling]. Schema-2 manifests share project, harness,
mode, and endpoint definitions; schema-1 configurations remain supported.

## Install and qualify

First install the home scripts and library with `make install`. Existing
configuration is preserved. Set `config/concurrency` in the installed home
configuration to the maximum number of simultaneous streams; `0` retains the
unlimited default. Slot records preserve admission accounting when a controller
exits while its system service is still active. Incoming mail remains queued
when all slots are occupied.

As administrator, stop `mail-agent-firewall.service` and wait for its dependent
workload services to terminate before upgrading system components. Then run:

``` sh
make install-system
```

This installs mail-agent code under `/usr/local/libexec/mail-agent` and
`/usr/local/lib/mail-agent`, and trusted configuration under `/etc/mail-agent`.
It does not copy compilers, harness packages, credentials, or repositories.
`DESTDIR=/some/staging/root` stages these files without deploying them.
Installation invalidates prior qualification. Do not upgrade either executor
while its invocations are running.

Install the Landlock wrapper at `/usr/local/bin/landlock` and landrun
**0.1.17** at `/usr/local/bin/landrun`. Their resolved paths and ancestor
directories must be root-owned and not group- or other-writable. This
implementation requires landrun’s strict ABI 9 filesystem and IPC restrictions,
Linux cgroup v2, systemd with DynamicUser and the emitted hardening directives,
nftables with `socket cgroupv2`, polkit, and the existing mail-agent runtime
tools. It adds no Python runtime dependency, scheduling daemon, network
namespace, or bpftool requirement. Unsupported versions must be qualified in a
subsequent change; do not enable best-effort confinement to accommodate them.

Copy `system/system.example.json` to a root-owned deployment file. Define one
policy for each permitted `(project, driver, mode)` combination. IDs contain
lowercase letters, digits, and underscores, and start with a letter. Projects
are original absolute repository paths; an empty project denotes a stream
without a repository. Administrative preparation and transfers use the
project’s `execute` policy, or `research` when the project is empty. Native
invocation uses the mail’s mode. Missing combinations fail without legacy
execution.

Each policy selects project groups, the shared bare repository, and existing
runtime paths. Provision those groups and paths before qualification. All
configured paths must exist and have ordinary read/traverse permissions for the
dynamic user through its supplementary groups. Source repositories and runtime
dependencies are read-only. A configured executable or toolchain can remain in
its existing location, provided parent-directory access and systemd mount
restrictions permit it. A read-only bind mount to an approved location is
another option. Do not copy a toolchain into each stream.

Provision the shared repository with `git clone --bare --no-hardlinks` and
`core.sharedRepository=0660`, with a project group and setgid directories. The
object store must have no alternates or links to original objects. Existing
streams migrate by **reusing their currently registered shared repository** at
its existing path. Correct its group permissions during project maintenance,
with affected streams paused; do not run recursive permission changes while
agents execute. Shared objects, refs, hooks, and caches do not provide
integrity isolation between members of that project group. Trusted repository
preparation reads the original source. Native harnesses receive access to the
private checkout and approved shared Git storage, without a grant for the
original source directory. Configure Git’s safe-directory setting for the
approved shared repository and private worktrees in the trusted harness
configuration if the installed Git requires it.

Shared caches receive read/write access without direct execution permission.
Interpreters can still read their contents; this is not a prohibition on
interpreted code. Shared authentication refers to the interactive CLI’s
credential file. Grant the required group access and verify that interactive
login preserves it when replacing the file. Research reads credentials but
cannot refresh them. Other modes may write the approved file; a CLI that needs
to rename files in its parent directory must use interactive renewal or a
separately reviewed profile adjustment. Never expose an entire personal CLI
home merely to make renewal succeed. The private harness directory contains
session history and copies of approved configuration, not private copies of
shared credentials.

`allow` entries contain numeric IP addresses or prefixes, `family` (`ip` or
`ip6`), `protocol` (`tcp` or `udp`), and `port`. Define model API and DNS
access explicitly. Project-specific remote build caches get entries only in
that project’s policies. Research accepts IP traffic; it still uses the
restricted research tool profile and filesystem policy. pi may allow its chosen
local inference address and port; it requires separate qualification on its own
host. The example’s empty execute allowlist denies traffic. There is no
DNS-driven allowlist update or TLS interception.

Render the policy without installing it for review:

``` sh
mail-agent-system-config /path/to/deployment.json /path/to/new-rendered-directory
```

Install reviewed policy as root:

``` sh
/usr/local/libexec/mail-agent/mail-agent-system-admin configure /path/to/deployment.json
```

Configuration creates the submission and result groups, assigns the dispatcher
membership, installs templates and slice units, reloads systemd, then installs
the start-only polkit rule. Restart the dispatcher’s user manager/login session
so it receives its new supplementary groups. Audit other host polkit rules for
broader authority. Review generated CPU, memory, task, and runtime limits; use
administrator-owned unit drop-ins for deployment-specific values.

Install a root-owned `/etc/mail-agent/probes/default` acceptance script.
Optional `/etc/mail-agent/probes/POLICY` files override it for individual
authorizations. `system/probe.example.sh` documents required assertions and
exits unsuccessfully until replaced. `mail-agent-system-admin qualify` starts
each script as the real dynamic user in its policy cgroup and outer Landlock
domain, without reading submissions or executing an agent phase. Probes must
also exercise the installed inner profiles and native harness, including the
actual per-mode tool configuration. A script returning zero is an
administrator-supplied assertion; the command cannot infer whether that script
tested all required behavior.

Test approved HTTP/2 and QUIC, IPv4/IPv6 TCP and connected/unconnected UDP
denials, loopback/internal addresses, DNS, remote caches, filesystem and Unix
socket restrictions, no direct cache execution, shared login, history and
forks, and child termination. Use known reachable forbidden test receivers to
distinguish ACL rejection from unavailable services. Separately test rejected
arbitrary starts/property changes, missing/modified firewall policy,
unsupported Landlock, mode transitions, concurrent streams, and state reuse
after reboot. These are deployment acceptance requirements, not claims
established by the unit tests. pi remains unqualified until tested on its
inference host.

``` sh
/usr/local/libexec/mail-agent/mail-agent-system-admin qualify
```

Qualification requires the fixed cgroup hierarchy and records component hashes
and versions. Ordinary starts require the qualification marker; preflight also
checks component hashes, persistent slice identities, and the effective
nftables table against the loaded reference. Unknown cgroup paths, missing
filtering, modified policy, or unsupported strict Landlock prevent workload
execution. After changing configuration, profiles, probes, launchers, systemd,
the kernel, or relevant runtime components, repeat qualification. Local hash
checks cannot establish unchanged kernel behavior after an upgrade.

The firewall service owns only `inet mail_agent`. Never flush or replace it
outside that service while work is running. Stopping the firewall service stops
dependent workloads before deleting the table; starting it pins policy slices
before loading cgroup matches. Reconfiguration stops isolated work and disables
qualification. It does not retry interrupted model invocations. Review/remove
obsolete root-owned templates and slice units during configuration maintenance;
the new polkit rule permits only currently configured policy IDs.

## Transfer an existing stream

Backend records are dispatcher-owned `~/mail/.agent/streams/SESSION.json`
files. Existing workspaces without a record remain legacy. A new stream records
the default once; forks inherit their parent’s backend. Default changes do not
alter recorded streams. Use full session IDs and do not edit backend records
directly.

``` sh
mail-agent-stream ensure SESSION
mail-agent-stream pause SESSION
mail-agent-migrate inspect SESSION > SESSION.migration.json
mail-agent-migrate apply SESSION
mail-agent-stream show SESSION
```

Pause and transfer require an available execution lock and no active service.
Status 75 means the operation could not acquire an idle stream. Wait for the
current turn to finish; start-only authorization does not grant cancellation.
Mail arriving while paused remains queued. Inspection reads file metadata,
registration pointers, and object link counts without executing Git or reading
credentials. Its `ready` field is an inventory result, not proof of
continuation or successful transfer.

Transfer imports the working checkout, raw Git index, ignored/untracked files,
and private driver history into the dynamic-user state directory. It uses the
existing shared object store and creates `isolated/SESSION`; it does not create
a full repository copy. The supported legacy layout has a conventional Git
worktree registration and `refs/heads/mail/SESSION`. Alternate object stores,
source hardlinks, detached/custom legacy refs, invalid registrations, and
special files fail rather than guessing how to convert them. The installed
policy must name that same shared repository. Git operations run under a
separate strict Landlock domain with hooks and fsmonitor disabled.

The service exports a snapshot after import. Transfer compares all checkout
contents and symlink targets (excluding the new `.git` registration), the
index, HEAD, and harness history before changing the backend atomically.
Transferred files gain group read/traverse access for the exchange; ordinary
file contents and executable bits are retained. The old checkout and harness
remain available in dispatcher storage. Metadata, queue entries, costs, reply
ancestry, task IDs, and patch-mail baselines retain their existing records.
Migration leaves the stream paused:

``` sh
mail-agent-stream resume SESSION
```

Do a bounded continuation test for the installed harness before admitting long
work. Repeat it for replies to older turns. Claude copies a selected transcript
into the new checkout’s encoded project directory; Codex imports transcript
ancestry; pi retains session files. Native CLI behavior must be tested with the
installed versions, particularly shared credential renewal.

## Roll back and recover

To return to legacy execution, first pause the stream and export its
**current** private state:

``` sh
mail-agent-stream pause SESSION
mail-agent-migrate rollback SESSION
mail-agent-stream resume SESSION
```

Rollback requires the retained legacy checkout and its original shared
registration. It exports the current checkout, index, and history, saves the
previous legacy files, restores current files and the legacy branch ref, and
then selects legacy while still paused. It does not revert newer dispatcher
metadata or task records. It supports migrating back to system afterward.
Streams created directly on system have no retained legacy registration and
cannot use this rollback command; they remain isolated until retired or given
an explicitly provisioned legacy destination.

Transfers retain their inputs, exported snapshots, backups, and completion flag
under `~/mail/.agent/migrations/SESSION/`. `current` names the latest attempt.
A failed comparison or interrupted copy leaves admission paused. Inspect the
recorded backend and retained directories before resuming. Repeating `apply`
while still legacy reimports administrative state and compares it again;
repeating `rollback` while still system exports again. Neither command executes
a model. Do not resume after an incomplete rollback until the restore succeeds.
Delete transfer snapshots explicitly after validation and the chosen retention
period; they can contain large ignored build outputs and harness transcripts.

Normal task failures retain the existing behavior: one failure reply, no retry.
The dispatcher waits for any surviving service before publishing another
request. Its protected task record prevents invoking an already recorded task,
even if the controller failed before receiving the result. A fresh user reply
creates a new task. Completion deduplication does not make remote API effects
exactly once, and no model output is replayed to repair an uncertain result.

`mail-agent-log` reads exported diagnostic events; `mail-agent-details` uses
exported commit summaries. Neither opens private system workspaces. Journal and
workload text do not authorize routing or completion. Only fixed, bounded
results are imported after the service and its descendants terminate.

## Retention and final adoption

`mail-agent-forget SESSION` retires a system stream and clears its queue while
retaining protected records and private artifacts. After the chosen retention
period, an administrator can run:

``` sh
/usr/local/libexec/mail-agent/mail-agent-system-admin purge SESSION
```

Purge requires a retired system record and inactive policy instances. It masks
those instances and deletes their private state, submissions, and results. It
retains dispatcher metadata, migration backups, and shared Git refs. Remove
those separately during approved retention/project maintenance; do not prune
shared Git registrations while agents are working.

Once a project/harness combination is qualified and representative streams have
continued successfully, set `~/.config/mail-agent/backend` to `system` for new
streams. Migrate remaining legacy streams individually. Keep the home executor
installed as long as retained legacy streams or rollback requirements need it.

  [isolation handoff checklist]: isolation-handoff.md
  [maintained deployment tooling]: deployment.md
