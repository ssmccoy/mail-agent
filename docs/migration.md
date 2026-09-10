# Migration to system-service execution

## Implementation status

The runtime path interface, persistent backend records, admission controls, and
read-only migration inspection are implemented. The system-service executor,
privileged installer, nftables enforcement, constrained state transfer, and
backend switch operation are not implemented. Keep
`~/.config/mail-agent/backend` set to `legacy`. Selecting `system` records that
selection but cannot execute a task in this version; scheduling reports failure
without falling back to legacy execution.

This document specifies the migration procedure as well as the preparation
commands that work now. The later installation, transfer, validation, and
switch steps require the remaining implementation and host qualification.

## Install preparation without changing execution

Run `make install` with the existing prefix. It installs the runtime library
along with scripts and profiles. Existing configuration files, including the
new `backend` default, are preserved. Install scripts and their runtime library
together; avoid replacing them during a running invocation.

Backend records are dispatcher-owned JSON files in
`~/mail/.agent/streams/SESSION.json`. Their schema contains `schema`,
`backend`, `state`, and an optional `parent` session. Admission state is
`active`, `paused`, or `retired`. The dispatcher creates records atomically and
synchronizes them before scheduling. A pre-existing workspace without a record
is recorded as legacy, irrespective of the configured default. A new stream
uses the default once, and a fork inherits its parent’s backend. Later changes
to the default do not change recorded streams.

To inspect an existing stream’s selection, first record it if necessary:

``` sh
mail-agent-stream ensure SESSION
mail-agent-stream show SESSION
```

Use full session IDs for these administrative commands. Do not edit backend
records to perform a migration.

## Pause and inventory

``` sh
mail-agent-stream pause SESSION
mail-agent-migrate inspect SESSION > SESSION.migration.json
```

Pause requires the execution lock to be available. If a turn is running, the
command returns status 75 and leaves admission unchanged. Wait for that turn,
then repeat the command. Start-only system authorization will not grant
cancellation; cancellation must remain an administrative operation.

Incoming mail remains queued while paused. Both the scheduling path and the
worker check admission, so a previously scheduled worker cannot begin a turn
after pause. Migration inspection also acquires the execution lock. It counts
workspace, history, queue, and task files, reports fixed metadata file sizes,
and checks shared objects for multiple links, alternates, and a mismatched
worktree pointer. It does not invoke Git, execute repository configuration,
follow credential links, or read credential contents. It is an inventory, not a
content backup or proof of driver continuation. A successful inspection
currently always reports `ready: false` and `system-backend-unavailable`.

An aborted inspection or preparation can return to current execution with:

``` sh
mail-agent-stream resume SESSION
```

Resume makes queued work eligible for the existing scheduling timer. Retired
streams cannot resume. Retirement retains the backend record and lock file so a
previously scheduled worker cannot recreate a deleted workspace.

## Provision the target before transferring streams

Install administrator-owned launchers, profiles, configuration, service units,
and nftables policy before enabling the scoped polkit start authorization. Keep
ordinary home installation available. Qualify the firewall classifier,
IPv4/IPv6 TCP and UDP restrictions, permitted HTTP/2 and QUIC traffic, Landlock
filesystem and IPC restrictions, missing-policy failures, child termination,
and research-to-execute transitions before enabling the backend for any stream.
A successful `systemctl start` will not establish successful phase completion.

Choose project groups, API/DNS endpoints, exceptional build-cache endpoints,
resource limits, and retention duration. Expose existing toolchains through
read-only paths or mounts and scope shared writable caches by project. Connect
shared interactive authentication without copying credentials into each stream.
Test each harness’s authentication renewal and continuation. Qualify pi on its
own inference host; do not infer its connectivity from another harness.

## Transfer idle streams

Pause every stream whose shared repository or worktree registrations will be
changed, including legacy streams that will not migrate in this operation.
Prevent repository maintenance during the transfer. Continue accepting mail
into the existing queue. Under the execution locks, reconcile any previous unit
invocation and task record. An interrupted model invocation is failed work;
state transfer must not invoke it again.

Create a durable migration journal outside workload-writable storage. Record
the selected sessions, project repositories, source and destination paths,
source backend, target backend, and progress through inventory, transfer,
validation, and switch. Retain source state until validation and switching
succeed. An interrupted transfer must be resumable from this journal.

Preserve the following without generating replacement identities:

| State          | Required preservation                                                                                                                              |
|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| Mail           | Session IDs, queued task IDs and messages, original repository routing, fork ancestry, response IDs                                                |
| Dispatcher     | Turn ledger, task records and results, effort, cost, branch, patch base, last-mailed commit                                                        |
| Git            | Shared objects and refs, each worktree’s HEAD and index, staged changes, unstaged changes, untracked and ignored files, executable modes, symlinks |
| Harness        | Selected continuation IDs and the history necessary for follow-ups and forks from older replies                                                    |
| Authentication | References to the shared interactive credentials; no per-stream copies                                                                             |

Provision one shared bare repository per project, with the approved group and
permissions. Do not clone the full repository per stream. Resolve alternate
object stores and source-object hard links before making the destination
writable. Git’s `--no-hardlinks` option prevents object hard links in new local
clones; changing group permissions alone does not separate existing linked
objects. [Git clone documentation].

Import each private checkout into its managed stream directory through the
administrative transfer interface. Reconstruct or repair the registrations in
the shared repository and the checkout’s `.git` reference together. Preserve
the index separately from working files; recreating a checkout at HEAD alone
loses staged and uncommitted work. Moving a worktree and moving its shared Git
directory require corresponding registration repair. Handle submodules and
nested repositories explicitly; the basic worktree move operation does not
support every layout. [Git worktree documentation].

Reconstruct approved runtime configuration and credential references separately
from importing agent-generated history. Translate path-dependent harness state
using the driver adapter. Do not copy an entire interactive home or grant the
child stream access to its parent’s private directory. Preserve the history
needed by older replies, not just the latest transcript.

## Validate and switch

Compare the retained and imported file manifests, contents, Git refs, HEAD,
index, worktree changes, and dispatcher metadata. Verify driver continuation
and older-reply forks on controlled copies without invoking an outstanding mail
task. Verify constrained result export and confirm that the dispatcher can
inspect results without reading private system-managed directories.

Only after validation succeeds, atomically switch the existing stream record to
the target backend while admission remains paused. Record that switch in the
migration journal, synchronize both, then resume admission. New queued mail
retains its original identity and ordering. An importer must not overwrite
completed/failed task records or reset them to pending.

Test interruption before transfer, during transfer, before the backend switch,
and after the switch but before resume. Also test reboot persistence. A
partially transferred destination must never become an executable stream.

## Rollback and retention

Before the backend switch, leave the legacy backend selected. Restore any
shared Git registrations changed during transfer before resuming legacy work;
retaining files alone is insufficient if their worktree registrations moved.

After the switch, if isolated execution has modified workspace or harness
state, pause admission, wait for all descendants to terminate, and use the
constrained export/import interface to transfer that current state back.
Validate it before switching the backend record back. Do not select an obsolete
legacy directory by changing a flag. Keep task outcomes and delivered patch
bases current during rollback; never re-execute a completed or interrupted mail
task as a rollback action.

Retain source snapshots and migration journals for the configured retention
period. Retire streams before deleting private system-managed state. The
unprivileged dispatcher’s permission to start services will not authorize
private-state deletion, firewall edits, or cancellation. Keep the legacy
executor installed until its streams have migrated or retired.

  [Git clone documentation]: https://git-scm.com/docs/git-clone
  [Git worktree documentation]: https://git-scm.com/docs/git-worktree
