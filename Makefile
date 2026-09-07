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
CONFIG = $(PREFIX)/.config
UNITS = $(CONFIG)/systemd/user
SCRIPTS = $(notdir $(wildcard bin/*))
CONFIGS = $(filter-out projects.example,$(notdir $(wildcard config/*)))
PROFILES = $(notdir $(wildcard landlock/*))

install:
	install -d $(BIN) $(CONFIG)/mail-agent $(CONFIG)/landlock $(UNITS)
	install -m 755 $(addprefix bin/,$(SCRIPTS)) $(BIN)
	install -m 644 $(addprefix landlock/,$(PROFILES)) $(CONFIG)/landlock
	install -m 644 systemd/mail-agent-drain.service systemd/mail-agent-drain.timer $(UNITS)
	for file in $(CONFIGS); do \
	    test -e $(CONFIG)/mail-agent/$$file || \
	        install -m 644 config/$$file $(CONFIG)/mail-agent/$$file; \
	done
	test -e $(CONFIG)/mail-agent/projects || \
	    install -m 644 config/projects.example $(CONFIG)/mail-agent/projects
	@echo
	@echo "Installed. Next: make forward, then make enable."

# One .forward serves every address, so an alias added to the agents
# table needs nothing here. It governs plain mail too, which is why the
# inbox is named in it.
forward:
	install -d -m 700 $(PREFIX)/mail/inbox/cur $(PREFIX)/mail/inbox/new \
	    $(PREFIX)/mail/inbox/tmp
	install -d -m 700 $(PREFIX)/mail/.agent/queue $(PREFIX)/mail/.agent/lock \
	    $(PREFIX)/mail/.agent/work $(PREFIX)/mail/.agent/repos \
	    $(PREFIX)/mail/.agent/claude $(PREFIX)/mail/.agent/codex
	printf '%s/mail/inbox/\n|%s/bin/mail-agent-hook\n' \
	    '$(PREFIX)' '$(PREFIX)' > $(PREFIX)/.forward
	chmod 600 $(PREFIX)/.forward
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
	@for tool in postconf sendmail mhdr mshow mmime jq pandoc node w3m git \
	    flock systemd-run landrun; do \
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
