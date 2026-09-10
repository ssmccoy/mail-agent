# Runtime paths

`make install` installs the shared shell definitions in
`$PREFIX/lib/mail-agent/runtime.sh`. Each driver and its helpers use these
paths without copying executables or toolchains into a stream. Defaults retain
the existing home installation. The invoking account supplies overrides in its
service environment; phase requests cannot specify these values.

| Variable                      | Default                                   | Purpose                                                  |
|-------------------------------|-------------------------------------------|----------------------------------------------------------|
| `MAIL_AGENT_LIB`              | `$HOME/lib/mail-agent`                    | Trusted runtime definitions                              |
| `MAIL_AGENT_BIN`              | `$HOME/bin`                               | Mail-agent executables                                   |
| `MAIL_AGENT_CONFIG`           | `$HOME/.config/mail-agent`                | Instructions, tool profiles, and result transforms       |
| `MAIL_AGENT_PROFILES`         | `$HOME/.config/landlock`                  | Filesystem profiles                                      |
| `MAIL_AGENT_LANDLOCK`         | `$HOME/bin/landlock`                      | Installed confinement launcher                           |
| `MAIL_AGENT_EXECUTABLE`       | `$HOME/.local/bin/DRIVER`                 | Selected harness executable                              |
| `MAIL_AGENT_PACKAGES`         | Harness-specific package directory        | Runtime dependencies of that harness                     |
| `MAIL_AGENT_SHARED_STATE`     | Harness-specific configuration directory  | Approved configuration and legacy history source         |
| `MAIL_AGENT_AUTH`             | Interactive harness credential file       | Shared authentication, linked into private harness state |
| `MAIL_AGENT_REPOSITORIES`     | `$HOME/mail/.agent/repos`                 | Legacy shared Git repositories                           |
| `MAIL_AGENT_TOOLCHAIN`        | `$HOME/.proto`                            | Shared read/execute toolchain tree                       |
| `MAIL_AGENT_TOOLCHAIN_CONFIG` | `$HOME/.prototools`                       | Read-only toolchain configuration                        |
| `MAIL_AGENT_EXEC_PATH`        | Toolchain `shims`, `bin`, then `/usr/bin` | Harness command search path                              |
| `MAIL_AGENT_GO_CACHE`         | `$HOME/mail/.agent/go`                    | Shared read/write Go caches outside research             |
| `MAIL_AGENT_GIT_CONFIG`       | `$HOME/.config/git`                       | Read-only Git configuration                              |
| `MAIL_AGENT_INSTRUCTIONS`     | `$HOME/.claude/CLAUDE.md`                 | Shared read-only instructions                            |

Harness defaults are:

| Harness | Packages                                                        | Shared configuration       | Credentials                       |
|---------|-----------------------------------------------------------------|----------------------------|-----------------------------------|
| Claude  | `$HOME/.local/share/claude`                                     | `$HOME/mail/.agent/claude` | `$HOME/.claude/.credentials.json` |
| Codex   | `$HOME/.codex/packages`                                         | `$HOME/mail/.agent/codex`  | `$HOME/.codex/auth.json`          |
| pi      | `$HOME/.local/lib/node_modules/@earendil-works/pi-coding-agent` | `$HOME/.pi/agent`          | `$HOME/.pi/agent/auth.json`       |

Set harness-specific overrides in the environment of the corresponding driver
invocation. A single override of `MAIL_AGENT_EXECUTABLE` applies to whichever
driver is invoked; it is not a map from driver names to executables. An
installation serving multiple harnesses must select the appropriate environment
for each. No environment file is sourced from a repository or submission.

`mail-agent-launch` constructs filesystem arguments individually, preserving
spaces in configured paths. It derives shared Git access from dispatcher
metadata, never from the workload’s `.git` pointer. Credentials are granted
read-only in research and read/write in the other modes. Missing credentials
are not copied or synthesized. When present, the private harness state links to
the configured authentication path, so interactive replacement or renewal is
visible on subsequent access. Installations with credentials somewhere other
than these defaults must set `MAIL_AGENT_AUTH` to that shared path.

Writable history remains in `work/SESSION/harness/DRIVER`; working scratch
remains private to an invocation. These overrides do not grant the dispatcher
access to future DynamicUser state directories, implement an isolated backend,
or change the existing Landlock network policy. Administrator-owned runtime
installation, private state imports, and nftables enforcement remain separate
adoption work.

The system backend selects these paths from root-owned policy environment files
generated from `system.json`. It additionally sets `MAIL_AGENT_SYSTEM_SHARED`
to the approved project object store; requests cannot supply that override. Its
installer produces strict profiles without `best-effort` or Landlock TCP port
rules, because nftables supplies TCP/UDP address and port enforcement. See
[migration] for group access, shared interactive authentication, cache
permissions, toolchain provisioning, and required host qualification.

  [migration]: migration.md
