# Install the mail agent into a home directory.
#
#   make install     scripts, configuration, sandbox profiles, units
#   make spool AGENT=codex
#                    a maildir and a .forward for one agent
#   make enable      start the retry timer
#   make check       report what is missing
#   make mutt        the reader-side pieces, printed rather than installed

PREFIX ?= $(HOME)
BIN = $(PREFIX)/bin
CONFIG = $(PREFIX)/.config
UNITS = $(CONFIG)/systemd/user
AGENT ?= claude

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
	@echo "Installed. Next: make spool AGENT=claude, then make enable."

spool:
	install -d -m 700 $(PREFIX)/mail/$(AGENT)/cur $(PREFIX)/mail/$(AGENT)/new \
	    $(PREFIX)/mail/$(AGENT)/tmp
	install -d -m 700 $(PREFIX)/mail/.agent/queue $(PREFIX)/mail/.agent/lock \
	    $(PREFIX)/mail/.agent/work $(PREFIX)/mail/.agent/$(AGENT)
	printf '%s/mail/%s/\n|%s/bin/mail-agent-hook\n' \
	    '$(PREFIX)' '$(AGENT)' '$(PREFIX)' > $(PREFIX)/.forward+$(AGENT)
	chmod 600 $(PREFIX)/.forward+$(AGENT)
	@echo
	@echo "Link the credentials the agent should use, for example:"
	@echo "  ln -s ~/.claude/.credentials.json ~/mail/.agent/claude/"
	@echo "  ln -s ~/.codex/auth.json ~/mail/.agent/codex/"

enable:
	systemctl --user daemon-reload
	systemctl --user enable --now mail-agent-drain.timer

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

.PHONY: install spool enable check mutt
