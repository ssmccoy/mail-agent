# Reproducible system deployment

Maintain a schema-2 deployment manifest, starting from
`system/manifest.example.json`. The checked-in `system/hosts/superbird.json`
selects the seven available projects and repository-free research on superbird.
The three unavailable projects and pi are excluded.

The manifest defines common runtime paths and modes once, harness paths and
endpoint groups once per harness, and source/shared/cache paths once per
project. A project can select a subset of modes. An empty source requires
research only. Endpoint groups contain reviewed numeric addresses; rendering
never resolves DNS or changes the snapshot. Update the manifest and repeat
qualification when service addresses change. The superbird snapshot was
resolved on 2026-09-10. Credentials remain in their interactive-login files and
are never copied into the manifest, backups, or repository.

## Render and check

``` sh
make system-render MANIFEST=system/hosts/superbird.json OUTPUT=/tmp/superbird-rendered
make system-check MANIFEST=system/hosts/superbird.json PROJECT=foundry
```

The output directory must not exist. Rendering is deterministic and requires no
administrator access. The superbird manifest produces 58 fixed execution
authorizations, five network policies, and six slices including their parent.
Authorizations select exact project/harness/mode combinations; network policies
are shared whenever their effective allowlists match. Research has its own
unrestricted network policy. Mode transitions still terminate the previous
instance before starting its replacement.

`system-check` validates the selected project and runtime paths and prints a
JSON provisioning plan without changing files. Each source must have its own
`.git` directory. Shared Git alternates, symlinks, special files, and
overlapping storage paths require correction before provisioning. Existing
object hardlinks are reported and separated by the apply operation.

## Install once, provision once per project

Install the tested revision and the reviewed manifest as administrator:

``` sh
sudo make install-system
sudo install -m 644 system/hosts/superbird.json /etc/mail-agent/deployment.json
```

The strict Landrun 0.1.17 binary and profile wrapper must already be installed
at `/usr/local/bin/landrun` and `/usr/local/bin/landlock`. Provisioning uses
the existing Bash, Git, jq, util-linux, and ACL tools; it does not install
packages.

For each selected project, run:

``` sh
sudo /usr/local/libexec/mail-agent/mail-agent-system-project apply \
    /etc/mail-agent/deployment.json foundry
```

For superbird, project identifiers are `foundry`, `cloud_foundations`,
`network_artifacts`, `systems`, `dotfiles`, `mail_agent`, `landlock`, and
`research`. The last record provisions repository-free research storage.

Each invocation validates the root-owned manifest, rejects active isolated
services, and acquires the existing execution locks of affected legacy streams.
If a stream is running, it exits 75 before repository maintenance. Applying a
project invalidates host qualification and stops the firewall service before
changing permissions. Pause mail admission for the project during maintenance
so new streams cannot start against the repository being provisioned.

The command creates the declared groups, provisions the shared repository
without source hardlinks, sets group permissions and setgid directories,
creates the cache, grants source Git metadata access, and grants access to the
existing credential files. Missing approved harness configuration directories
receive minimal configuration files; existing files are preserved. It then
renders and installs the manifest through the existing administrator command.
This configures all declared authorizations, but their runtime paths become
available as each project is provisioned. Complete every project before
qualification.

Repeat applications preserve refs and credentials. Before changing an existing
shared repository, apply copies it to a new root-private directory under
`/var/backups/mail-agent-PROJECT.*`. The directory also records the manifest
and ACLs before modification. These backups are retained; choose a retention
period and delete obsolete backups separately. If provisioning is interrupted,
inspect the repository and backup before retrying. No automatic restore is
attempted.

Credential ACLs must be reapplied after interactive login replaces a credential
file. Research cannot renew credentials. Native renewal behavior remains part
of host qualification. Applying a project does not select the system backend,
migrate sessions, or create a qualification marker.

## Qualification

Install a single root-owned `/etc/mail-agent/probes/default` acceptance script
that selects assertions using `MAIL_AGENT_SYSTEM_DRIVER`,
`MAIL_AGENT_SYSTEM_MODE`, and `MAIL_AGENT_SYSTEM_PROJECT`. An optional
`/etc/mail-agent/probes/POLICY` overrides it for a specific generated
authorization. Every selected authorization still runs inside its actual
service and network policy; shared definitions do not skip project-specific
checks.

`system/probe.example.sh` remains an incomplete checklist and exits 78. It must
not be used as a passing acceptance test. Native harness, network, IPC,
failure, migration, and reboot qualification remain required; see the
[isolation handoff]. The maintained real-filesystem smoke test can be run with
`make test-isolation`; it uses disposable files and invokes shell assertions
through the actual profiles, without model calls or a qualification marker.

  [isolation handoff]: isolation-handoff.md
