# mail-agent

mail-agent runs coding agents in response to email. Send a request to
`you+claude@your.host` or `you+codex@your.host`, with a project name in the
subject. The agent reads the request, works in a Git worktree, and replies in
the mail thread. Commits are sent as separate patches for review and
application with `git am`.

    To: claude
    Subject: mail-agent: retry backoff on the poller

    !execute
    The poller retries immediately on a 503. Give it exponential
    backoff with a cap of thirty seconds.

Postfix, the queue, and the workers run on one host. Agents use network access
for model requests and other tasks. The source repository is read-only to the
agent; execute turns can modify the thread’s worktree.

## Requirements

Use Linux with Landlock support and a launcher that reads the supplied `.cfg`
profiles. Execute profiles currently enable `best-effort`; without kernel
support, filesystem restrictions may not be enforced. Investigate and plan
profiles require enforcement.

| Dependency                              | Purpose                                        |
|-----------------------------------------|------------------------------------------------|
| postfix                                 | Local delivery with `recipient_delimiter = +`  |
| systemd user instance                   | Transient workers and retry timer              |
| [landrun] and a `.cfg` profile launcher | Filesystem and network restrictions            |
| mblaze                                  | Mail parsing and composition                   |
| jq                                      | Routing, event processing, and usage reports   |
| pandoc                                  | Markdown rendering and text wrapping           |
| awk                                     | HTML and numeric formatting                    |
| git                                     | Clones, worktrees, `format-patch`, and `am`    |
| w3m                                     | Attachment and Markdown display                |
| mutt                                    | Mail interface and patch application shortcuts |
| `claude` or `codex` or `pi`             | Agent CLI                                      |

Claude must support `--output-format stream-json` and `--settings`. Codex must
support `exec fork` and `--json`.

Configure Postfix for local delivery to Maildir. Delivery to mbox can escape
patch `From` lines and prevent `git am` from reading them.

    sudo postconf -e "home_mailbox = mail/inbox/" \
        "recipient_delimiter = +" "inet_interfaces = loopback-only" \
        "default_transport = error: no relay host configured"

These settings restrict Postfix to loopback connections and disable nonlocal
delivery.

## Installation

    make check                  # report missing dependencies
    make install                # install scripts, profiles, units, and config
    make forward                # create Maildirs and forwarding files
    make enable                 # enable the retry timer

Link the credentials and instructions for the agents you use. Credential
symlinks allow the interactive CLI and mail driver to use the same refreshed
tokens.

    ln -s ~/.claude/.credentials.json ~/mail/.agent/claude/
    ln -s ~/.claude/CLAUDE.md ~/mail/.agent/claude/CLAUDE.md
    ln -s ~/.codex/auth.json ~/mail/.agent/codex/
    ln -s ~/.claude/CLAUDE.md ~/mail/.agent/codex/AGENTS.md

Configure repositories in `~/.config/mail-agent/projects`, one key and path per
line:

    project                 /home/you/code/example/project
    mail-agent              /home/you/code/example/mail-agent

Run `make mutt` to print the example Mutt configuration. Adapt it for
`~/.muttrc`, including your address in the aliases. Configure `~/.mailcap`
using `mutt/mailcap.example`; that file also describes the required Markdown
conversion for w3m.

## Addresses and threads

`~/.config/mail-agent/agents` maps address suffixes to drivers and models:

    # alias       driver   model
    claude        claude   -
    fable         claude   fable
    haiku         claude   haiku
    codex         codex    -
    sol           codex    gpt-5.6-sol
    mini          codex    gpt-5.4-mini

A model of `-` uses the CLI default. To configure another alias, edit the
installed table and the source `config/agents`, then run `make forward`. That
target reads the source table to create `~/.forward+<alias>` files. Mutt
aliases are optional address abbreviations.

Agent-addressed mail is saved in `~/mail/agents/` and passed to the hook. The
bare `~/.forward` saves ordinary mail and replies in `~/mail/inbox/` and passes
a copy to the hook.

The subject text before the first colon selects a project. Leading `Re:` and
`Fwd:` prefixes are ignored. An unknown project produces a reply listing the
configured projects, except in research mode. The project and agent alias are
selected when a thread starts; changing the subject later does not select a
different repository.

Reply in the thread to continue work. Session identifiers in `Message-Id` and
`References` associate replies with their conversations. A message with no
matching thread starts a new session. Project sessions use separate worktrees
from one shared clone per source repository. New shared clones use group
permissions and copy objects without hard links to the source. Each driver
receives access only to its assigned project’s Git store. Existing shared
clones require a separate permissions and hard-link migration before use by
dynamic system users.

## Modes and directives

Place directives before the request. The default mode is `!investigate`.

| Directive      | Repository edits | Result                      |
|----------------|------------------|-----------------------------|
| `!investigate` | Disabled         | Findings                    |
| `!plan`        | Disabled         | Plan                        |
| `!execute`     | Enabled          | Reply and committed patches |
| `!research`    | Disabled         | Findings and source links   |

Modes can change between messages in a thread. For example, investigate a
problem, request a plan, then send `!execute` to implement it. All three
drivers use strict Landlock profiles with read-only access to the worktree and
shared Git storage outside execute mode. Claude also uses its CLI permission
mode. Required Landlock restrictions must be supported; these profiles do not
enable best-effort enforcement.

New research threads run in an empty directory without a repository, even if
the subject matches a configured project. They use network access to research
the request. Followups default to research until another mode is requested.

    To: claude
    Subject: NVMe write amplification under zoned namespaces

    !research
    How do zoned namespaces affect write amplification?
    Include sources and describe the implementation costs.

Research requested within an existing code thread retains read access to its
repository. An `!execute` request in a thread without a repository receives an
explanation without starting an agent turn.

Research uses dedicated Landlock profiles for all drivers. The working
directory and any assigned repository are read-only; shared Git objects are
readable only for an assigned worktree. Build caches are not writable. Each
turn has private temporary storage, deleted after response extraction. Other
modes also use private temporary directories; non-execute scratch and shared
build caches have read/write permission without file execution. CLI history and
runtime metadata use a private directory for each mail stream. Research
credentials are read-only; renew authentication through the interactive CLI.
Landlock applies the same filesystem permissions to the CLI and its tools, so
runtime state remains writable by both. Research therefore permits history and
working-area writes, without granting writes to the checkout or build caches.

Codex disables ancestor project discovery for repository-free threads and
enables live web search for research. HTTPS access remains available under
Landlock. Repository-free threads retain the research filesystem restrictions
when explicitly switched to investigate or plan.

`!branch <name>` selects the starting branch. On a later message, it fetches
and switches to the requested branch and resets the patch base to that branch’s
tip. Without this directive, a new thread uses the source repository’s default
branch. An unknown branch produces an error reply without running the agent.

    To: claude
    Subject: mail-agent: backport the poller fix

    !execute
    !branch release-2
    Adapt the main-branch fix to the older client.

`!details` returns the recorded session details without running the agent or
waiting in the turn queue.

### Tool profiles

Each harness and mode selects a separate JSON argument array from
`~/.config/mail-agent/tools-<driver>-<mode>.json`. Edit these installed files
to configure tools independently for investigate, plan, execute, and research.
Installation preserves existing profiles. Missing or invalid profiles prevent
CLI execution. Arguments are passed without shell evaluation or word splitting.

Claude uses `--tools`; pi uses `--tools` across built-in and extension tools.
Their research defaults allow file reading, writing, editing, and searching,
with Claude’s web tools also enabled. Research omits shell and delegation
tools. Claude disables inherited MCP configuration and user/project setting
sources for research. Its research permission mode permits file operations,
while Landlock restricts the writable paths.

Codex research disables shell, unified execution, delegation, apps, hooks, and
plugin discovery in its tool profile. It replaces inherited MCP configuration
with the required `mail-agent-files` server, exposing only `read`, `write`, and
`edit`. File reads remain subject to Landlock; writes and exact-match edits are
restricted to the private research working area. Requests and file reads are
limited to 1 MiB. The helper uses the existing shell, jq, and system utilities;
it exposes no command-execution tool. Codex web search remains enabled.

Tool profiles are trusted configuration. These flags must be supported by the
installed CLI versions. The offline tests verify argument selection and actual
file-server operations; qualification with each installed CLI is still
required. Changing a tool profile does not expand Landlock filesystem
permissions.

### Runtime installation and migration preparation

Drivers accept explicit paths for installed tools, runtime dependencies,
configuration, credentials, and caches. Defaults preserve the home
installation; see [runtime configuration]. The shared runtime library is
installed in `~/lib/mail-agent` and must be upgraded with the scripts.

Each stream records its backend outside the agent’s writable directories.
Existing streams retain legacy execution, and forks inherit the parent’s
backend. `mail-agent-stream pause SESSION` suspends admission without dropping
queued mail; `resume` enables admission again.
`mail-agent-migrate inspect SESSION` inventories a paused stream without
invoking Git or reading credential contents. See the [migration procedure] for
commands, preservation requirements, and rollback.

Keep `~/.config/mail-agent/backend` set to `legacy`: the system backend and
nftables integration are not implemented. Selecting an unavailable backend
reports scheduling failure without executing the task locally.

### Effort

Use `X-Mail-Effort: <level>` or `!effort <level>` to select `low`, `medium`,
`high`, `xhigh`, or `max`. Values are case insensitive. The selection persists
until changed; `default` restores the driver’s default. Empty, unknown, or
conflicting values prevent the turn from running.

    To: astra
    Subject: foundry: diagnose the poller hang

    !effort max
    The poller stops responding about once a week. Find the cause.

When no explicit effort control is present, `Priority: non-urgent` selects
`low`, `Priority: normal` selects `medium`, and `Priority: urgent` selects
`high`. This controls effort, not queue order. Invalid or conflicting Priority
values prevent execution unless an explicit effort control takes precedence.
With neither control, the session retains its existing setting.

A model that does not support the selected level produces a driver failure. The
pi driver ignores effort.

Replies and patches report these headers:

| Header                 | Values                                             |
|------------------------|----------------------------------------------------|
| `X-Mail-Effort`        | Selected level, `default`, or `unsupported` for pi |
| `X-Mail-Effort-Source` | `message`, `session`, or `default`                 |
| `X-Mail-Mode`          | Mode of the model turn                             |

Effort headers describe configuration, not measured reasoning usage. Validation
replies and details responses do not report a model turn mode.

The example Mutt configuration provides compose shortcuts: Alt-e followed by
`d`, `l`, `m`, `h`, `x`, or `M` selects default, low, medium, high, xhigh, or
max. Each shortcut replaces the current draft’s effort header and restores the
editor setting. It does not change other drafts or body directives. Delete any
conflicting `!effort` line or make it agree with the header. Mutt’s `E` command
also allows direct header editing.

The example displays `X-Label: effort=<level>` in the index, colors high effort
yellow, and colors xhigh and max bright red.

## Replies and patches

The reply body is Markdown wrapped to 79 columns. The example mailcap
configuration displays it through Pandoc and w3m. Attachments describe the
turn:

| Attachment              | Contents                          |
|-------------------------|-----------------------------------|
| `reasoning.html`        | Recorded reasoning and tool calls |
| `steps.txt`             | One summary per step              |
| `usage.html`            | Reported or estimated cost        |
| Plan file, when present | The written plan                  |

HTML attachments render in the pager. Tool calls use command, diff, or path
notation as appropriate. Raw agent records remain on disk and are not attached.

Execute turns send one patch message per commit, threaded under the reply.
Commit messages are wrapped paragraph by paragraph to 72 columns; indented
figures and diffs are preserved. Set `MAIL_AGENT_WRAP` to change that width.
Uncommitted edits are not delivered.

Reply to a patch and comment below the relevant quoted hunk. Inline quotations
are retained in the agent’s request. Trailing quotations and their attribution
lines are stripped.

To apply patches in Mutt, tag each with `t`, or use `T` with `~s PATCH`, then
press `A`. The example enables `pipe_split` so `git-am-mail` receives each
message separately. Start Mutt in the target repository or one of its
subdirectories. The applier checks the expected repository before applying the
patches.

| Key      | Menu         | Action                                                              |
|----------|--------------|---------------------------------------------------------------------|
| `A`      | Index, pager | Apply patches to the repository containing Mutt’s working directory |
| `esc-A`  | Index, pager | Apply patches to the request’s source repository                    |
| `W`      | Attachments  | Open an attachment in w3m                                           |
| `ctrl-d` | Index, pager | Delete the thread and retire its session                            |

Retiring a session deletes its worktree and queued requests. Undoing a mailbox
deletion does not restore the session. Diff colors apply only to messages with
`[PATCH` in the subject, so Markdown list items are not colored as deletions.

When an agent needs a decision, its reply ends with numbered questions and
stated defaults. Respond by number or below each quoted question:

    !execute
    1. Collect metrics only.
    2. Return unsupported for now.

## Session inspection

`mail-agent-sessions` lists each thread’s agent, activity, turn count, cost,
and initial subject. Activity is determined from the worker’s session lock and
queued messages.

`mail-agent-details [session]` reports the project, branch, patch base, turns,
costs, commits, and latest steps. Sending `!details` in the thread returns this
report by mail without running a model turn.

`mail-agent-log [-f] [session]` prints recorded steps. Use `-f` to follow new
steps. Supply a session identifier or prefix; without one, the command selects
the running session if exactly one is active. Codex events do not contain
timestamps, so its step output omits them. Older turns without event records
have no steps to display.

## Agent access

landlock profiles grant read-only access to the source repository. Writable
paths include the execution worktree, shared clone storage, driver state,
credential files, build caches, and temporary directories. Consult `landlock/`
for the full permissions. The profiles exclude SSH keys, GitHub and Kubernetes
credentials, Teleport certificates, and interactive session transcripts. They
do not grant access to the Postfix maildrop directory.

The profiles allow TCP connections to port 443. Network access is available in
every mode, including research. It is not restricted to model API requests.

Go caches are configured under `~/mail/.agent/go`, and proto’s executable shims
are included in `PATH`. Other toolchains may require environment settings and
filesystem permissions in the profiles.

Codex runs with its internal sandbox disabled because it cannot initialize
inside the Landlock sandbox. Its non-execute profile grants read and execute
access to the worktree instead of write access. These restrictions depend on
the kernel and launcher enforcing the profile.

The agent cannot push to the source repository. Apply the mailed commits with
`git am` to change that repository.

## Operation

Turns within a session run sequentially in arrival order. Separate sessions can
run concurrently. A new message waits for the active turn to finish.

Each queued message identifies one task. Before invoking a driver, the worker
records that task under `~/mail/.agent/tasks/<session>/<task>/`. Driver
failures and timeouts are terminal and produce a failure reply; request another
attempt by sending another message. A task with an existing execution record is
never run again automatically, including after interruption. Completed output
remains in the task directory for inspection if mail composition is
interrupted.

The delivery hook, forks, and drain timer use the same dispatch command. A
scheduling failure produces an immediate reply when no existing session worker
can consume the message. The five-minute timer schedules waiting messages; it
does not retry failed agent tasks. Postfix does not retry after the delivery
hook has returned successfully.

    systemctl --user list-timers mail-agent-drain.timer
    journalctl --user -u 'mail-agent-*' -n 50
    find ~/mail/.agent/queue -type f

The default turn timeout is one hour. Set `MAIL_AGENT_TIMEOUT` to change it.
This limits how long an unresponsive process can prevent subsequent turns in
the session from running.

### Drivers and usage

Claude and Codex use the same worker and reply format, with separate drivers
for CLI invocation and event conversion. Aliases using the same driver share
credentials; each mail stream has its own CLI history and runtime metadata
under `work/<session>/harness/<driver>`. The configured model distinguishes
aliases. Existing streams import their selected continuation transcript from
the former shared history directory; forks copy only the selected parent
transcript.

| Setting                | Claude                        | Codex                               |
|------------------------|-------------------------------|-------------------------------------|
| State directory        | `~/mail/.agent/claude`        | `~/mail/.agent/codex`               |
| Credential link target | `~/.claude/.credentials.json` | `~/.codex/auth.json`                |
| Instruction file       | `CLAUDE.md`                   | `AGENTS.md`                         |
| Edit restriction       | CLI permission mode           | Landlock profile                    |
| Usage report           | Reported dollar cost          | Token counts and estimated API cost |

Codex does not report a per-turn ChatGPT subscription charge. The driver
estimates Standard API cost using its configured model rates and the reported
uncached input, cached input, and output token counts. Reasoning tokens are
included in output tokens. The estimate excludes tool-call charges, cache-write
premiums, long-context multipliers, regional processing, and service-tier
adjustments, which aggregate CLI usage does not identify.

### Files

| Path                                  | Purpose                                    |
|---------------------------------------|--------------------------------------------|
| `~/.forward`                          | Inbox delivery and hook invocation         |
| `~/.forward+<alias>`                  | Agent Maildir delivery and hook invocation |
| `~/bin/mail-agent-hook`               | Queue incoming requests                    |
| `~/bin/mail-agent-run`                | Run a turn and compose its response        |
| `~/bin/mail-agent-dispatch`           | Schedule queued tasks through user systemd |
| `~/bin/mail-agent-phase`              | Execute a validated driver request         |
| `~/bin/mail-agent-task`               | Record a task and preserve its result      |
| `~/bin/mail-agent-render`             | Render transcripts as HTML                 |
| `~/bin/mail-agent-drain`              | Retry queued requests                      |
| `~/bin/mail-agent-usage`              | Report costs                               |
| `~/bin/mail-agent-sessions`           | List sessions                              |
| `~/bin/mail-agent-details`            | Inspect a session                          |
| `~/bin/mail-agent-log`                | Display recorded steps                     |
| `~/bin/git-am-mail`                   | Apply mailed patches                       |
| `~/.config/landlock/mail-agent-*.cfg` | Sandbox profiles                           |
| `~/.config/mail-agent/steps*.jq`      | Driver event transformations               |
| `~/.config/mail-agent/agents`         | Alias, driver, and model mapping           |
| `~/.config/mail-agent/projects`       | Project key and repository mapping         |
| `~/mail/.agent/repos/`                | Shared repository clones                   |
| `~/mail/.agent/work/<session>/repo/`  | Session worktree                           |
| `~/mail/.agent/queue/<session>/`      | Queued requests                            |
| `~/mail/.agent/work/<session>/cost`   | Per-turn cost records                      |
| `~/mail/.agent/claude/`               | Claude configuration and session records   |
| `~/mail/.agent/codex/`                | Codex configuration and session records    |

### Troubleshooting

If the reply addresses the subject but ignores the body, check that the request
contains a plain text MIME part.

If `git am` fails, check the expected repository path printed by the applier
and confirm that the target revision is compatible with the patch.

If no reply arrives, inspect the queue and systemd journal. A queued message
may be waiting for authentication or a retry. If the message is no longer
queued, inspect the journal for a failure after processing began.

## Isolation adoption

The accepted system-service and nftables design is recorded in [the adoption
document]. The current implementation includes strict non-execute profiles,
per-mode tool configuration, per-stream CLI state, a phase request interface,
and terminal task records. Execution still uses user services and the current
Landlock network rules. No nftables policy or dynamic system-user backend is
installed by `make install`.

  [landrun]: https://github.com/Zouuup/landrun
  [runtime configuration]: docs/runtime.md
  [migration procedure]: docs/migration.md
  [the adoption document]: docs/isolation.md
