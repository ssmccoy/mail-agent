# Install the mail agent into a home directory.
#
#   make install     scripts, configuration, sandbox profiles, units
#   make forward     the inbox maildir and the .forward that feeds the hook
#   make enable      start the retry timer
#   make notify      desktop notifications for new inbox mail
#   make check       report what is missing
#   make mutt        the reader-side pieces, printed rather than installed

PREFIX ?= $(HOME)
BIN = $(PREFIX)/bin
LIB = $(PREFIX)/lib/mail-agent
CONFIG = $(PREFIX)/.config
UNITS = $(CONFIG)/systemd/user
SCRIPTS = $(notdir $(wildcard bin/*))
CONFIGS = $(filter-out projects.example instructions.md,$(notdir $(wildcard config/*)))
PROFILES = $(notdir $(wildcard landlock/*))

install:
	install -d $(LIB) $(BIN) $(CONFIG)/mail-agent $(CONFIG)/landlock $(UNITS)
	install -m 755 $(addprefix bin/,$(SCRIPTS)) $(BIN)
	install -m 644 lib/runtime.sh $(LIB)
	install -m 644 $(addprefix landlock/,$(PROFILES)) $(CONFIG)/landlock
	install -m 644 systemd/mail-agent-drain.service systemd/mail-agent-drain.timer $(UNITS)
	install -m 644 config/instructions.md $(CONFIG)/mail-agent/instructions.md
	for file in $(CONFIGS); do \
	    test -e $(CONFIG)/mail-agent/$$file || \
	        install -m 644 config/$$file $(CONFIG)/mail-agent/$$file; \
	done
	test -e $(CONFIG)/mail-agent/projects || \
	    install -m 644 config/projects.example $(CONFIG)/mail-agent/projects
	@echo
	@echo "Installed. Next: make forward, then make enable."

# The bare .forward governs plain mail and the agents' replies, which are
# addressed to the plain address, so it files them in the inbox and pipes
# a copy to the hook. A message to you+<alias> is outbound to an agent; a
# .forward+<alias> per row of the agents table files it in mail/agents
# and pipes it to the hook, so a sent message reaches the agent and is
# readable afterwards without crowding the inbox it will be answered in.
forward:
	install -d -m 700 $(PREFIX)/mail/inbox/cur $(PREFIX)/mail/inbox/new \
	    $(PREFIX)/mail/inbox/tmp
	install -d -m 700 $(PREFIX)/mail/agents/cur $(PREFIX)/mail/agents/new \
	    $(PREFIX)/mail/agents/tmp
	install -d -m 700 $(PREFIX)/mail/.agent/queue $(PREFIX)/mail/.agent/lock \
	    $(PREFIX)/mail/.agent/work $(PREFIX)/mail/.agent/repos \
	    $(PREFIX)/mail/.agent/claude $(PREFIX)/mail/.agent/codex
	printf '%s/mail/inbox/\n|%s/bin/mail-agent-hook\n' \
	    '$(PREFIX)' '$(PREFIX)' > $(PREFIX)/.forward
	chmod 600 $(PREFIX)/.forward
	for alias in $$(awk '/^[^#]/ && $$1 { print $$1 }' config/agents); do \
	    printf '%s/mail/agents/\n|%s/bin/mail-agent-hook\n' \
	        '$(PREFIX)' '$(PREFIX)' > $(PREFIX)/.forward+$$alias; \
	    chmod 600 $(PREFIX)/.forward+$$alias; \
	done
	@echo
	@echo "Link the credentials each driver should use:"
	@echo "  ln -s ~/.claude/.credentials.json ~/mail/.agent/claude/"
	@echo "  ln -s ~/.claude/CLAUDE.md ~/mail/.agent/claude/CLAUDE.md"
	@echo "  ln -s ~/.codex/auth.json ~/mail/.agent/codex/"

enable:
	systemctl --user daemon-reload
	systemctl --user enable --now mail-agent-drain.timer

notify:
	install -d $(UNITS)
	install -m 644 systemd/mail-agent-notify.path \
	    systemd/mail-agent-notify.service $(UNITS)
	systemctl --user daemon-reload
	systemctl --user enable --now mail-agent-notify.path
	@echo
	@echo "Reader-side, in ~/.muttrc:"
	@echo "  set new_mail_command = \"notify-send -a mutt 'New mail: %f' '%n new'\""

check:
	@for tool in postconf sendmail mhdr mshow mmime jq pandoc awk w3m git \
	    flock realpath stat sync systemd-run landrun; do \
	    command -v $$tool >/dev/null 2>&1 || echo "missing: $$tool"; \
	done
	@command -v landlock >/dev/null 2>&1 || \
	    echo "missing: landlock (the launcher that reads .cfg profiles)"
	@command -v claude >/dev/null 2>&1 || echo "missing: claude (optional)"
	@command -v codex >/dev/null 2>&1 || echo "missing: codex (optional)"
	@postconf -h recipient_delimiter 2>/dev/null | grep -q . || \
	    echo "postfix: recipient_delimiter is unset"
	@postconf -h home_mailbox 2>/dev/null | grep -q / || \
	    echo "postfix: home_mailbox is unset, replies will go to /var/mail"
	@echo "check complete"

mutt:
	@cat mutt/muttrc.example

.PHONY: install spool enable notify check mutt

# Offline tests use private homes, local repositories, and captured mail.
test:
	./test/run

test-shells:
	TEST_SHELL=/bin/dash ./test/run
	TEST_SHELL='/bin/bash --posix' ./test/run

.PHONY: test test-shells

test-syntax:
	./test/check

.PHONY: test-syntax
