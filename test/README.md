# Tests

Run `make test` for the offline Bats suite. Run `make test-shells` to execute
shell programs, including nested invocations, under dash and Bash in POSIX
mode. Run `make test-syntax` for shell, Perl, and JavaScript syntax checks.
These targets do not install software or contact model services.

Install bats-core, mblaze, Git, jq, Node, Perl, pandoc, and the Linux utilities
`flock` and `timeout`. The suite also uses standard filesystem and text tools
with the GNU options already required by the application. The runner reports
missing required dependencies before executing tests. Bash is a test
dependency; production shell scripts continue to use POSIX sh.

To select cases, use `./test/run --filter 'retry'`. The runner forwards its
arguments to Bats and produces TAP output, suitable for a CI job invoking the
same Make targets. Each test receives a private home and temporary directory
under `test/.run.*`; the runner deletes these after Bats exits. Run the suite
through `test/run`, rather than invoking Bats directly, to keep its temporary
files inside the checkout.

## Execution

Tests execute the production programs as subprocesses. The helper creates
wrappers that select the requested shell for installed shell commands; it does
not modify their contents or source them into Bash. Non-shell programs use
their existing interpreters. The child environment excludes credentials and
user Git configuration and defines synthetic Git identities.

Mail parsing and composition, Git repositories and worktrees, patch generation
and application, locking, jq filters, and rendering use real tools. Test
executables capture outgoing mail and scheduling requests. Driver tests replace
the agent CLI and Landlock launcher with executables that record arguments and
emit small synthetic event streams. Worker tests use a driver implementing its
file and exit-status interface.

The application provides three overrides, retaining its normal defaults:

| Variable | Default | Purpose |
|----|----|----|
| `MAIL_AGENT_SENDMAIL` | `sendmail` | Executable receiving outgoing messages with `-t` |
| `MAIL_AGENT_SYSTEMD_RUN` | `systemd-run` | Executable receiving worker scheduling arguments |
| `MAIL_AGENT_OUTPUT_DIR` | `/tmp/mail-agent` | Existing writable directory for Codex final output |

Command overrides name one executable, without arguments. The output directory
must be writable within the selected sandbox when using a real launcher.

Use small fixtures and assertions about observable behavior. Check stable text
with exact comparisons and generated identifiers through their relationships.
Keep real mail and Git operations in integration cases rather than implementing
replacement parsers or repositories. Use real locks and bounded waits for
concurrency tests; every test must finish its subprocesses before cleanup.

## Coverage and limits

The suite covers transformations, the three driver interfaces, routing,
complete turns and patch application, retries and timeouts, branch changes,
fork creation and retirement, session details, and retrying independent
sessions while one is locked. It requires no mail server, model account,
running user systemd instance, or Landlock installation.

Launcher assertions verify argument selection, not actual sandbox enforcement.
Real systemd scheduling and Landlock permissions need a separate Linux
integration suite. CLI fixtures do not establish compatibility with a newly
released agent CLI.

Two identified defects remain separate from this harness change: outgoing mail
uses `X-Mail-Agent` while the delivery hook’s loop check reads
`X-Claude-Agent`, and delivery failures can advance queue or patch state.
Regression tests for those defects should accompany their fixes; this suite
does not establish successful handling of those conditions.
