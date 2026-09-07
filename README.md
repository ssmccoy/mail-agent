# mail-agent

Answer mail with a coding agent. A message to `you+claude@your.host` or
`you+codex@your.host` names a project in its subject, and an agent reads it,
works in a clone of that repository, and replies in thread: prose as the body,
its reasoning and cost attached, and any commits sent after it as a patch
series you apply with one keystroke in mutt.

Everything runs on one host. Postfix delivers locally, the agent runs under
landlock with the repository read-only, and nothing leaves the machine except
the model API call.

    To: claude
    Subject: foundry: retry backoff on the poller

    !execute
    The poller retries immediately on a 503. Give it exponential
    backoff with a cap of thirty seconds.

The harness is the same for both agents; only the driver differs.

## Requirements

A Linux kernel with Landlock (5.13 or newer; a kernel without it, or WSL, falls
back to best effort, which is not a boundary).

| what                                                | why                                                      |
|-----------------------------------------------------|----------------------------------------------------------|
| postfix                                             | local delivery, with `recipient_delimiter = +`           |
| systemd, user instance                              | one transient unit per turn, and the retry timer         |
| [landrun] and a launcher that reads `.cfg` profiles | the sandbox                                              |
| mblaze                                              | reading and building the mail                            |
| jq                                                  | routing, the step summaries, the cost tables             |
| pandoc                                              | rewrapping replies and plans                             |
| node                                                | the two renderers                                        |
| git                                                 | clones, `format-patch`, `git am`                         |
| w3m                                                 | reading the rendered parts (reader side)                 |
| mutt                                                | the reader side, and the keystroke that applies a series |
| `claude` or `codex`                                 | at least one, whichever agents you want                  |

Claude needs a version that speaks `--output-format stream-json` and
`--settings`; codex needs `exec resume` and `--json`. Both were current as of
Claude Code 2.1.263 and codex-cli 0.149.0.

Postfix must deliver to a maildir, or replies land in an mbox where the `From`
line of every patch is escaped and `git am` refuses the series:

    sudo postconf -e "home_mailbox = mail/inbox/" \
        "recipient_delimiter = +" "inet_interfaces = loopback-only" \
        "default_transport = error: no relay host configured"

The last two make the host local-only, which is what keeps a spool that
executes code out of reach of anything but this machine.

## Installing

    make check                  # report what is missing
    make install                # scripts, profiles, units, configuration
    make spool AGENT=claude     # a maildir and a .forward for one agent
    make spool AGENT=codex
    make enable                 # the retry timer

Then link the credentials each agent should use, so a refreshed token is
written in one place rather than diverging between two configuration
directories:

    ln -s ~/.claude/.credentials.json ~/mail/.agent/claude/
    ln -s ~/.claude/CLAUDE.md ~/mail/.agent/claude/CLAUDE.md
    ln -s ~/.codex/auth.json ~/mail/.agent/codex/
    ln -s ~/.claude/CLAUDE.md ~/mail/.agent/codex/AGENTS.md

Name the repositories the agents may work in, one per line, in
`~/.config/mail-agent/projects`. Then `make mutt` prints the reader-side
configuration to fold into your `~/.muttrc`, and `mutt/mailcap.example` belongs
in `~/.mailcap`.

## Sending

Address the mail to `claude` or to `codex`, both mutt aliases for the extension
addresses. The address decides which agent answers, and the thread keeps it: a
reply goes back to whichever one started it. The subject names the project; the
first line of the body names the mode.

    To: claude
    Subject: foundry: retry backoff on the dcfab poller

    !execute
    The poller retries immediately on a 503. Give it exponential
    backoff with a cap of thirty seconds.

The word before the first colon in the subject selects the repository from
`~/.config/mail-agent/projects`. It is read once, when the thread starts;
editing it in a later reply changes nothing, so a thread cannot be re-pointed
at another repository halfway through.

Reply to a reply to continue the same session. The session id travels in the
`Message-Id`, so any client that keeps a `References` header keeps the
conversation. A message that matches no existing thread starts a new session
with a fresh clone.

## Modes

The first line of the body selects what the turn may do. Without one, the turn
is an investigation.

| directive      | edits                  | reply             |
|----------------|------------------------|-------------------|
| `!investigate` | refused by the sandbox | findings          |
| `!plan`        | refused by the sandbox | a plan            |
| `!execute`     | allowed                | prose and patches |

`!details` is not a mode: it answers from what is already on disk, replying
with the thread’s details and running no turn.

`!branch <name>` says which branch to work from. On the first message of a
thread it selects what gets cloned; later it fetches that branch and moves the
thread onto it, and the patch base moves with it, so a series is always
measured from the tip the work started on. Without it the thread gets whatever
the repository’s HEAD points at. A branch that does not exist gets a reply
saying so and no clone.

    To: claude
    Subject: foundry: backport the poller fix

    !execute
    !branch release-2
    Same change as on main, adapted to the older client.

Modes mix freely within a thread: investigate until the shape of the problem is
clear, ask for a plan, then send `!execute` in the same thread and the agent
commits with everything it has already learned.

Refusal in the first two is enforced by permission mode, not by asking
politely. An `!investigate` turn told to edit a file will explain the change it
would have made and commit nothing.

## Patches

An execute turn sends its commits as messages of their own, one per commit,
threaded under the reply that acts as their cover letter. The diff is the body,
so it reads in the pager and colours like a diff.

To answer one, reply to that patch and write under the hunk you mean. The
quoted diff comes back with your comment, in the session that wrote it, so
“this loop is wrong” arrives attached to the loop.

To apply, tag the patches you want (`t` on each, or `T` with `~s PATCH`) and
press `A`. Mutt hands each tagged message to git-am-mail in turn, which is why
`pipe_split` is set: concatenated instead, git am reads a series as one patch
and squashes it into a single commit.

## When it asks you something

A turn that needs a decision ends with a numbered `Questions` section, each
line saying what will be assumed if you say nothing. Answer in the same thread,
by number:

    !execute
    1. gather only
    2. return unsupported for now

Or reply with `r` and write under each quoted question. Inline quoting
survives; the quote a reply trails behind it, and the attribution above it, are
dropped before the agent sees the message, so leaving them costs nothing.

## Reading the reply

The reply itself is the body: markdown, rewrapped to 79 columns, rendered
through pandoc into w3m by `~/.mailcap`, so a table arrives drawn as one.
Commits do not ride along with it; they follow as their own messages, described
above. What is attached is the record of the turn.

| part             | what it is                                             |
|------------------|--------------------------------------------------------|
| `reasoning.html` | the turn’s thinking and every tool call                |
| `steps.txt`      | one line per step of the turn                          |
| `usage.html`     | what the turn cost: money for Claude, tokens for codex |
| the plan’s name  | the plan itself, when a turn wrote one                 |

Both HTML parts render in the pager automatically. Tool calls appear in the
notation of the tool: `> command` for a shell call, `-`/`+` lines for an edit,
a path for a read or write. The raw records behind the reasoning are not
mailed; they stay under `~/mail/.agent/claude/projects/`.

Diff colouring is scoped to patch mail by a message-hook on the `[PATCH`
subject, since the rules that paint a removal red cannot tell one from a
markdown bullet.

| key     | in           | does                                      |
|---------|--------------|-------------------------------------------|
| `A`     | index, pager | apply the series to the tree mutt runs in |
| `esc-A` | index, pager | apply it to the repository the agent used |
| `W`     | attachments  | open a part in w3m, for scrolling         |

Start mutt from the project directory and `A` applies the patches there. Any
subdirectory works. When the tree is not the one the series was written
against, the applier says so before it tries.

## Watching a turn

A turn takes minutes and says nothing until it replies. Two tools read the same
state the worker does, from outside the mail.

    mail-agent-sessions

lists a line per thread: which agent answers it, whether it is running, waiting
behind a running turn, or idle on disk, with the turns and cost spent so far
and the subject that started it. Running means the thread’s lock is held, which
is the test the worker itself makes.

    mail-agent-details [session]

prints what is known about one thread: its subject and project, the branch and
the base its patches are measured from, every turn with what it cost, the
commits standing on the base, and the steps of the last turn. Replying
`!details` to any message in a thread returns the same text by mail, answered
at delivery and never queued, which is how to read a thread from somewhere
other than this host.

    mail-agent-follow [-1] [session]

prints one line per step as it happens: reasoning, each tool call, and the size
of what it returned. Both agents are read the same way; the events behind the
lines differ, and codex’s carry no clock, so its lines have none. A thread
whose last turn predates this recording has nothing to show until it runs
again.

    01:39:51  edit repo/projects/dcfab/pkg/lang/bind/selector.go  +9 -4
    01:39:55  $ go test ./pkg/lang/...
    01:39:58    ← 47 lines

A session id or any prefix of one selects the thread; with no argument it picks
the running one, when exactly one is running. `-1` prints what has happened and
stops instead of following.

## Projects

`~/.config/mail-agent/projects` maps a subject key to a repository:

    foundry                 /home/you/code/example/foundry
    cloud-foundations       /home/you/code/example/cloud-foundations

Add a line to make a repository reachable. An unknown key gets a reply listing
the ones that exist, so a typo costs a round trip rather than silence.

## What the agent can reach

The repository goes into the sandbox read-only and is cloned into the thread’s
working directory, which is the only writable path besides the agent’s own
configuration directory. Ssh keys, `gh` and kube credentials, teleport
certificates, and the transcripts of interactive sessions are all outside it.
The agent cannot inject mail either: the postfix maildrop spool is unwritable,
so a reply cannot answer itself.

Commits are the delivery mechanism. The clone’s origin is read-only, so nothing
the agent does reaches a real tree until `git am` puts it there.

## Operating it

Turns within a thread run one at a time, in arrival order; separate threads run
in parallel. A message that arrives mid-turn waits for the lock rather than
interrupting.

A turn that cannot run keeps its message queued. The usual cause is an expired
login, in which case the reply says so once, and a timer retries every five
minutes until it works. Nothing else re-fires a delivery, because postfix
considered it complete the moment the hook returned.

    systemctl --user list-timers mail-agent-drain.timer
    journalctl --user -u 'mail-agent-*' -n 50
    find ~/mail/.agent/queue -type f          # anything waiting

A turn is stopped after an hour; set `MAIL_AGENT_TIMEOUT` to change it. The
limit exists because subagents can stall a batch run indefinitely, and a
stalled turn holds the thread’s lock.

## The two agents

|                  | Claude                 | codex                              |
|------------------|------------------------|------------------------------------|
| address          | `you+claude`           | `you+codex`                        |
| spool            | `~/mail/claude`        | `~/mail/codex`                     |
| state            | `~/mail/.agent/claude` | `~/mail/.agent/codex`              |
| credentials      | symlink to `~/.claude` | symlink to `~/.codex`              |
| instructions     | `CLAUDE.md`            | `AGENTS.md`, a symlink to it       |
| edits refused by | permission mode        | landlock, with the clone read-only |
| reports          | cost in dollars        | token counts                       |

codex runs with its own sandbox turned off, because it cannot initialise one
inside landlock’s. Landlock is then the only boundary, which is why an
investigate or plan turn gets a profile whose clone is mounted read and execute
rather than read, write and execute: the refusal is the filesystem’s, not the
agent’s.

## Where things are

| path                                         | what                              |
|----------------------------------------------|-----------------------------------|
| `~/.forward+<agent>`                          | delivery to the spool and hook    |
| `~/bin/mail-agent-hook`                      | queues an arriving message        |
| `~/bin/mail-agent-run`                       | runs one turn and replies         |
| `~/bin/mail-agent-render`                    | transcript to HTML                |
| `~/bin/mail-agent-drain`                     | retries queued messages           |
| `~/bin/mail-agent-usage`                     | the cost table                    |
| `~/bin/mail-agent-sessions`                  | one line per thread               |
| `~/bin/mail-agent-follow`                    | a thread’s steps as they happen   |
| `~/bin/git-am-mail`                          | applies a mailed series           |
| `~/.config/landlock/mail-agent-claude.cfg`   | Claude’s sandbox                  |
| `~/.config/landlock/mail-agent-codex.cfg`    | codex’s sandbox                   |
| `~/.config/landlock/mail-agent-codex-ro.cfg` | the same, clone read-only         |
| `~/.config/mail-agent/steps-codex.jq`        | the step summary, codex events    |
| `~/.config/mail-agent/projects`              | subject key to repository         |
| `~/mail/claude/`                             | what was sent to the agent        |
| `~/mail/.agent/work/<session>/`              | the thread’s clone                |
| `~/mail/.agent/queue/<session>/`             | messages not yet answered         |
| `~/mail/.agent/work/<session>/cost`          | a line per turn, with its cost    |
| `~/mail/.agent/claude/`                      | the agent’s own CLAUDE_CONFIG_DIR |

## When something looks wrong

A reply that answers the subject and ignores the body means the body never
arrived; check that the message has a plain text part.

`git am` refusing a series usually means the tree is not the one it was written
against. The applier prints the expected path first.

No reply at all: look for the message in the queue and the unit in the journal.
A message still queued is waiting for a login or a retry; a message gone with
no reply means the turn failed after consuming it, which the journal will show.

  [landrun]: https://github.com/Zouuup/landrun
