# Isolated mail-agent execution

This is the accepted deployment design implemented by the optional system
backend. The current executor remains available during each change. Never
automatically switch a failed isolated task to the legacy executor.

## Execution interface

Investigate, plan, and research prohibit writes to the checkout and shared Git
metadata. Every harness and mode has a configurable tool profile. Research
omits shell tools and permits private working files plus the stream’s CLI
history and runtime metadata. Credentials remain shared with interactive login;
research cannot refresh the shared credential files.

A versioned phase request separates the approved driver invocation from mail
composition. The caller supplies workspace and output paths, while the request
contains only its schema, task identity, driver, mode, model, and effort. The
phase writes an outcome with its task identity and exit status. The dispatcher
records tasks outside agent-writable directories and never executes a recorded
task again. There is no automatic model replay or checkpoint recovery protocol.

Runtime paths are explicit; see [runtime configuration]. Backend records
preserve each stream’s selection, forks inherit that selection, and admission
can be paused while incoming mail remains queued. The [migration procedure]
documents installation, qualification, state transfer, rollback, and retention.
The home executor remains the default. The system backend has offline protocol
tests but requires qualification on each deployment host before activation.

## System-service backend

The unprivileged dispatcher starts administrator-installed system service
templates through start-only polkit rules. Use the existing mail session UUID
as the stream identity. Record a backend per stream; changing the installation
default affects new streams only.

Use DynamicUser and one persistent StateDirectory per stream. Different mode
variants must be serialized before directory setup as well as during execution.
The fixed launcher and its configuration must not be writable by the dispatcher
or workload. Apply stream confinement before reading a submission and narrower
filesystem permissions before invoking an agent. Require supported Landlock
filesystem and IPC restrictions; unsupported enforcement prevents execution.

Keep submissions dispatcher-owned and read-only to the service. Provide a
separate result exchange with fixed filenames, output limits, and validation
before importing results into dispatcher storage. The workload cannot alter
routing, recipients, scheduling records, or protected completion metadata. Stop
all descendants before collecting final results or changing phase policy.

Observe unit state and invocation identity after dispatcher interruption. Wait
for an active service; report an interrupted task without starting it again.
Starting an active instance does not enqueue another turn. Keep queue ordering,
per-stream serialization, and configurable global admission limits in the
dispatcher.

## Shared repositories and tools

New clones already use group permissions and avoid source-object hard links.
Keep a group-writable bare clone per project and a private checkout per stream.
Use project-specific groups and shared Git permissions, and serialize
repository maintenance. Sessions sharing writable objects and refs do not have
independent Git integrity. Keep the original repository read-only.

Expose installed compilers, debuggers, agent executables, and proto versions
through approved read-only paths or mounts. Do not duplicate toolchains per
stream. Use read/write, non-executable working areas and caches, with
executable build products in the execute workspace. Shared writable caches can
influence other builds; their scope must be explicit.

## Network policy

Use administrator-owned nftables rules selected by harness, project, and mode.
Combine inference endpoints with explicit project exceptions such as remote
build-cache services. Specify IPv4/IPv6 addresses, protocol, and destination
port. Requests cannot supply firewall rules or endpoint addresses.

The implementation classifies sockets through persistent cgroup slices, without
NFTSet or dynamic UID matching. Default denial applies to the workload class
independently of its per-policy match. Missing enforcement, stale slice
identities, and unsupported layouts fail before an agent starts. Policy reload
stops dependent workloads before replacing rules. No bpftool is required.

Research has broad network access, read-only project/documentation access,
private read/write working space, and persistent per-stream CLI history. Stop
research and all its descendants before starting an execute invocation with its
restricted ACL. File execution restrictions do not prohibit interpretation of
code; filesystem, tool, IPC, and network restrictions work together.

Pi has its own inference policy, initially a loopback address and TCP port.
Make the endpoint configurable for a remote GPU cluster or hosted inference.
Actual pi connectivity must be tested on its deployment host.

## Qualification and migration

The offline suite verifies request handling, tool arguments, file operations,
queue behavior, and mail output. It does not establish real CLI compatibility,
Landlock enforcement, system-service isolation, or nftables behavior.

Before enabling the system backend, test approved HTTP/2 and QUIC requests;
denied unlisted IPv4/IPv6 TCP/UDP destinations; blocked unauthorized service
operations; denied filesystem and IPC access; failure with missing enforcement;
child termination; phase transitions; authentication renewal; driver
continuation; reboot persistence; and dispatcher interruption. Test real
compilation and debugging against the shared toolchain. Pi connectivity remains
a separate host qualification.

Migrate only idle streams. Preserve mail/thread IDs, queued task IDs, fork
ancestry, repository and patch bases, effort, costs, and driver continuation.
Validate imported state before switching the recorded backend. Retain the old
state until migration succeeds. Returning after isolated execution changes the
workspace requires explicit state transfer.

Adapt inspection and live logs to dispatcher records and constrained exports.
Retirement disables dispatch; deletion of private system-managed state is an
administrative retention operation. Start-only authorization does not grant
cancellation or deletion. Keep the legacy executor until streams have migrated
or retired.

## Implemented policy selection and verification

Each configured project/harness/mode combination generates a separate
`mail-agent-POLICY@SESSION.service` template and `mailagent-POLICY.slice`. All
policy slices belong to the dedicated `mailagent.slice`. The firewall service
creates them before loading numeric destination/protocol/port rules. Its
nftables input and output chains classify sockets by those persistent cgroup
ancestors; unmatched policy descendants are denied. Research policies accept IP
traffic. The service templates serialize policy changes for a stream before
systemd configures its reused state directory.

Preflight verifies the expected cgroup path, persistent slice identities,
qualified component hashes, and the complete installed nftables table. The
outer launcher applies strict Landlock before reading the request. Git and
harness execution enter narrower domains; agent-writable paths exclude the
control record and result exchange. Device access is constrained by the private
device mount and Landlock path grants, with an empty capability set. No device,
network, or IPC descriptors are passed from the dispatcher.

The main phase exits before `ExecStopPost` exports results. A second preflight
checks policy again. Protected output records contain the request ID, task ID,
invocation ID, and exit status. The client waits for termination, checks named
bounded results, and imports them into dispatcher storage. Live event exports
are diagnostic only. Raw workload mail headers do not select recipients or
repository routing. Agent tasks are never automatically replayed;
administrative imports may be repeated while a stream remains paused.

The exact classifier and strict confinement must pass the deployment probes in
[migration procedure]. The implementation does not treat unit properties, an
attached program, or an unqualified successful unit start as evidence of
network enforcement. Administrators own the probes and policy lifecycle; direct
nftables table replacement during execution is outside that lifecycle.

The relevant upstream interfaces are the [nftables socket expressions],
[systemd managed execution], and [landrun strict sandbox implementation].

  [runtime configuration]: runtime.md
  [migration procedure]: migration.md
  [nftables socket expressions]: https://netfilter.org/projects/nftables/manpage.html
  [systemd managed execution]: https://man7.org/linux/man-pages/man5/systemd.exec.5.html
  [landrun strict sandbox implementation]: https://github.com/Zouuup/landrun
