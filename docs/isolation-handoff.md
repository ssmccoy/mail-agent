# Isolation project handoff

## Remaining work

The system executor, dispatcher integration, migration, and rollback are
implemented. The project is **not yet qualified for production use on any host
by this work**. Offline tests substitute systemd and confinement commands; they
establish protocol behavior, not actual network, filesystem, or native harness
enforcement.

The remaining deliverables are a host-specific deployment configuration,
working qualification probes, evidence from real integration and failure tests,
any corrections those tests require, and a completed rollout. This document is
the completion checklist. [Migration] contains the detailed commands and
[runtime configuration] describes runtime paths.

## Local verification on 2026-09-10

Base revision: `e32d5c64a0b18e3222ae583a182a4eb589f45c02`, with the
working-tree changes described below. The selected deployment target is this
host, `superbird`, with dispatcher account `scott`. This record does not
establish deployment qualification.

- OS: Debian GNU/Linux forky/sid.
- Kernel after the user upgrade: `7.1.13+deb14-amd64`; cgroup filesystem:
  `cgroup2fs`.
- systemd: `262~rc1-2`; after reboot the manager reports `degraded` because
  `systemd-modules-load.service` fails to load missing NVIDIA modules.
- nftables: `1.1.7-1`; polkit: `127-3`; Git: `2.55.0`.
- Landlock wrapper repository revision:
  `46a730b478af2c29c59921ac76facd359aa90d1e` (installed wrapper contents have
  not been compared with this revision).
- Existing `mail-agent-drain.timer`: active.
- Installed Landrun: `0.1.17`, matching the corrected version requirement.
  Upstream introduced strict ABI 9 support in [Landrun v0.1.17]. The previous
  `0.1.18` requirement was an implementation and documentation error;
  correcting it does not establish kernel ABI support or qualification.
- Deployment configuration: `/etc/mail-agent/system.json` is absent.
- `make test-syntax`: passed.
- `make test-shells`: passed all 118 tests under dash and all 118 under bash
  POSIX mode.

A strict probe outside the workspace sandbox returned status 0 after the user
upgraded the host to `7.1.13+deb14-amd64`:

``` sh
landrun --rox /usr --rox /lib --rox /lib64 -- /usr/bin/true
```

The earlier probe on `6.18.12+deb14-amd64` returned status 1 because that
kernel exposed ABI 7. The upgrade resolves that prerequisite failure. This
small probe verifies strict sandbox setup and command execution; it does not
qualify the service policies, network filtering, or native harnesses.

## Maintained deployment tooling

Use [Reproducible system deployment] and the checked-in
`system/hosts/superbird.json` manifest. They replace the temporary deployment
JSON and provisioning scripts from this session. The manifest selects the seven
available projects with Claude and Codex in all four modes, plus
repository-free research. The user excluded fabric-solver, gitops, and
net-tools because their configured paths are absent. pi remains excluded.

The manifest derives 58 fixed execution authorizations from shared definitions,
using five network policies. `mail-agent-system-project check` validates one
project without mutation; `apply` provisions that project with repository and
ACL backups. Both commands are maintained in the repository. See the deployment
guide for installation and one command per project.

The user installed the system executables and strict profiles before this
refactor. Their ownership was verified as root outside the workspace sandbox.
The maintained-tooling changes require another `make install-system` before
use. No project provisioning, backend switch, or stream migration has occurred;
no qualification marker has been created.

The system harness launcher no longer grants the original source directory to
native harnesses. This prevents the dotfiles project at `/home/scott` from
granting access to unrelated home files. Trusted repository preparation still
has source access. The real filesystem smoke tests are maintained as
`make test-isolation`; passing them does not qualify the outer service, network
policy, IPC, or native harness behavior.

## 1. Record the destination and deployment inputs

- [ ] Record the repository revision, target OS, kernel, systemd, nftables,
  polkit, Git, Landlock wrapper revision, and native harness versions. Keep
  versions and test results together in the deployment record. No tested
  kernel/systemd compatibility matrix has been produced yet.
- [ ] Provide cgroup v2 and the interfaces required by the generated units and
  nftables rules. The qualification command accepts exactly
  `landrun version 0.1.17`; the design expects strict Landlock ABI 9 support.
  If the host needs another version or cgroup layout, change and test the
  implementation rather than enabling best-effort confinement.
- [ ] Select the dispatcher account, mail delivery configuration, user manager,
  project groups, original repository paths, and shared bare repositories.
- [ ] For every permitted project/harness/mode combination, specify a policy in
  a deployment JSON derived from `system/system.example.json`. Include an
  `execute` policy for repository preparation and administrative transfers;
  repository-free streams instead require a policy with an empty project and
  mode `research`. Reserve the service instance name `qualification` for
  probes.
- [ ] Supply each policy’s runtime paths: `binary`, `packages`,
  `configuration`, `auth`, `cache`, `git_config`, `instructions`, `toolchain`,
  and `toolchain_config`. Provision every path and its parent traversal
  permissions. Use the same approved object store across a project’s mode
  policies.
- [ ] Specify numeric IPv4/IPv6 addresses or prefixes, TCP/UDP protocols, and
  ports for model APIs, the resolver, and explicit project build-cache
  exceptions. Research deliberately permits IP traffic. Provide an operational
  procedure for endpoint changes; automatic DNS-based updates are not supplied.
- [ ] Set per-mode tool profiles, CPU/memory/task/runtime limits, global
  concurrency, and retention periods for private state, results, submissions,
  migration snapshots, dispatcher records, and shared Git refs.

## 2. Provision and install without changing the default

- [ ] Keep `~/.config/mail-agent/backend` set to `legacy`. Install the home
  scripts with `make install` while existing invocations are idle. Verify the
  destination’s mail routing, reply delivery, and scheduling timer separately
  from isolation.
- [ ] Provision shared repositories with project group permissions and setgid
  directories, without source-object hardlinks or Git alternates. For
  migration, reuse each legacy checkout’s registered shared repository at its
  existing path. Pause affected streams before repository permission
  maintenance.
- [ ] Expose existing compilers, debuggers, system tools, and harness packages
  through approved paths and permissions. No per-stream toolchain copy is
  required. Keep shared cache access read/write without direct execution and
  check for overlapping grants that would also permit execution.
- [ ] Connect shared interactive credentials. Verify read access for the
  dynamic identity, preservation of access after interactive login replaces the
  file, and actual renewal behavior. Research cannot refresh shared
  credentials. Atomic renewal requiring parent-directory writes is not
  automatically handled; use interactive renewal or implement a narrowly
  reviewed adjustment.
- [ ] As administrator, install the trusted wrapper and landrun at
  `/usr/local/bin/landlock` and `/usr/local/bin/landrun`. Stop the firewall
  service and its dependent workloads before upgrades, then run
  `make install-system`.
- [ ] Render the deployment JSON with `mail-agent-system-config` and review the
  generated templates, slice hierarchy, filesystem grants, nftables table, and
  polkit rule. Install it using the root command
  `/usr/local/libexec/mail-agent/mail-agent-system-admin configure DEPLOYMENT.json`.
- [ ] Restart the dispatcher’s login/user manager to acquire submission/result
  group membership. Check that other polkit rules do not grant it broader
  service control. Verify that trusted executables and configuration cannot be
  modified by the dispatcher or workloads.

## 3. Implement the missing qualification tests

**The actual probe scripts still need to be written.**
`system/probe.example.sh` is an outline that exits 78, not an executable
acceptance suite. Install a root-owned `/etc/mail-agent/probes/default`, with
optional `/etc/mail-agent/probes/POLICY` overrides for individual
authorizations. The `qualify` command runs these scripts inside the real
service’s outer Landlock domain and network policy. It does not automatically
exercise the narrower harness domain or determine whether a script returning
zero tested everything required.

Implement assertions for each applicable row below. Use disposable test streams
and controlled, reachable test receivers. Record the expected outcome and the
observed result; a network timeout alone does not prove filtering.

| Area | Required evidence |
|----|----|
| Allowed network | Successful requests negotiating HTTP/2 and QUIC to approved endpoints; working approved DNS, inference, and project build-cache access. |
| Denied network | Rejected unlisted external, internal, and loopback traffic over IPv4/IPv6 TCP and UDP, including connected/unconnected UDP and socket rebinding. Test both traffic directions and confirm the cgroup classifier applies. |
| Research | Broad IP access with the real research tool profile; no shell/delegation tools; read-only repository and documentation; writable private history and research files. |
| Filesystem/IPC | Execute writes only approved project/state/cache paths. Investigate and plan cannot modify checkout or shared Git metadata, including through Claude. Test denied access to other streams, control records, result exchange, host credentials, devices, Unix sockets, and administrative interfaces. |
| Cache permissions | Direct execution from shared caches and research storage fails; normal cache reads/writes work. Interpreters can still read files, as accepted in the design. |
| Native harnesses | Claude, Codex, and pi use their configured tools, shared credentials, private history, continuation, and older-reply forks. Include a real build/debug session with the existing toolchain. Qualify pi on its own inference host. |
| Export | Replies, patch mail, attachments, plans, usage, and logs reach the dispatcher through the bounded exchange with correct group permissions; workload content cannot select recipients or repository routing. |

Some tests require a separate administrator-controlled test runner outside the
service. **That runner is not supplied by `mail-agent-system-admin qualify`.**
Write one or record repeatable manual procedures for these scenarios:

- [ ] Missing or modified firewall policy, changed slice identities, altered
  qualified components, and unavailable required Landlock support prevent
  third-party execution. Observe a protected execution marker or equivalent,
  rather than relying only on a reported error.
- [ ] Arbitrary/transient service starts, property changes, and stop requests
  fail for the dispatcher; only installed authorized instance starts succeed.
- [ ] Research-to-execute transitions terminate all prior children before the
  new ACL and dynamic-user workspace setup. Concurrent streams retain separate
  private state. A start of an active instance does not enqueue another task.
- [ ] Dispatcher interruption while a service runs does not lose serialization
  or global concurrency accounting. An uncertain task gets a terminal failure,
  never automatic model replay or legacy fallback. Later queued tasks still
  run.
- [ ] Firewall service stop/restart and reconfiguration terminate dependent
  work in the required order. Do not perform uncontrolled firewall replacement
  on a production host to test this.
- [ ] State and history survive service exit, dynamic identity changes, and a
  reboot. Qualify the actual post-reboot cgroup and firewall behavior.
- [ ] Staged, unstaged, ignored, and untracked files, index state, symlinks,
  executable permissions, reply ancestry, queued mail, and patch baselines
  survive migration and rollback. The transfer command’s content comparison
  does not replace a permissions or native continuation test.
- [ ] Interrupted imports/restores remain paused and can be recovered without
  losing the last valid state. Exercise retention on disposable retired
  streams.

Run `make test-shells` and `make test-syntax` on the implementation used for
qualification. Run the real deployment tests as well. Fix failures and repeat
relevant tests; do not manually create a qualification marker to bypass them.
Run the root command
`/usr/local/libexec/mail-agent/mail-agent-system-admin qualify` to execute the
installed per-policy probes and record hashes and versions. Preserve the
external test evidence alongside that record. Repeat qualification after
relevant host, policy, or runtime changes.

## 4. Decide whether existing sessions must move machines

Backend migration is implemented **on one host**. There is no automated
cross-host session relocation command. Continuing this initiative on another
system does not require moving existing sessions: qualifying fresh test streams
there and leaving existing sessions on their original host is supported.

If existing sessions must move, complete a separate transfer procedure first:

- [ ] Stop admission and ensure neither controllers nor system services remain
  active on the source. Back up dispatcher configuration and the complete
  relevant `~/mail/.agent` state, including queues, task records, work
  metadata, histories, shared repositories, and migration backups. Arrange mail
  routing so source and destination cannot process the same queue concurrently.
- [ ] Preserve absolute repository and worktree paths, or implement and test
  relocation of Git registrations, project mappings, and path-encoded harness
  history. `mail-agent-migrate apply` is not a path-rewriting utility.
- [ ] For an already isolated stream, plan administrative backup/restore of its
  system-managed state and shared repository registration, or first roll it
  back to a retained legacy destination. Copying dispatcher metadata alone does
  not copy the private workspace. Do not copy transient `/run` state or treat a
  qualification marker copied from the source as qualification of the target.
- [ ] Provision credentials through interactive login on the destination and
  qualify its policies independently. Validate queue ownership, continuation,
  history, patches, and rollback before admitting live mail there.

## 5. Roll out and establish completion

- [ ] Migrate one paused representative legacy stream using `ensure`, `pause`,
  `migrate inspect`, and `migrate apply`; inspect the result before `resume`.
  Test continuation, an older-reply fork, and a rollback after new isolated
  work.
- [ ] Resolve or explicitly exclude unsupported migration layouts: alternates,
  source hardlinks, custom/detached legacy refs, invalid registrations, or
  special files. The supported legacy ref is `refs/heads/mail/SESSION`.
- [ ] Keep retained legacy destinations while rollback is required. A stream
  created directly on system has no such destination and cannot use the
  existing rollback command without additional provisioning/implementation.
- [ ] Migrate remaining eligible streams individually. Change the default to
  `system` only after the selected project/harness policies and representative
  streams pass. Existing backend records remain unchanged by the default.
- [ ] Assign responsibility for endpoint updates, requalification, interactive
  authentication, failure monitoring, backups, and retention. Private-state
  purge does not delete dispatcher records, migration backups, or shared Git
  refs; those require separate maintenance.

The initiative is complete for a deployment when its selected policies have
recorded passing real-host evidence, production streams use the intended
backend, recovery and rollback have been demonstrated, and these operating
procedures have an owner. Deferred harnesses such as pi must remain explicitly
excluded from that deployment’s completion claim until separately qualified.
Client/server authentication management and automatic endpoint discovery remain
outside the accepted scope.

  [Migration]: migration.md
  [runtime configuration]: runtime.md
  [Landrun v0.1.17]: https://github.com/Zouuup/landrun/releases/tag/v0.1.17
  [Reproducible system deployment]: deployment.md
