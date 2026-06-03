PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
SYSTEMD_USER_DIR := $(PREFIX)/lib/systemd/user

SCRIPTS := wayvnc-on-demand
UNITS := wayvnc-on-demand.service

.PHONY: install uninstall check

install:
	@for s in $(SCRIPTS); do \
		install -Dm755 bin/$$s "$(DESTDIR)$(BINDIR)/$$s"; \
	done
	@for u in $(UNITS); do \
		install -d "$(DESTDIR)$(SYSTEMD_USER_DIR)"; \
		sed "s|@BINDIR@|$(BINDIR)|g" "systemd/user/$$u" > "$(DESTDIR)$(SYSTEMD_USER_DIR)/$$u"; \
		chmod 644 "$(DESTDIR)$(SYSTEMD_USER_DIR)/$$u"; \
	done

uninstall:
	@for s in $(SCRIPTS); do rm -f "$(DESTDIR)$(BINDIR)/$$s"; done
	@for u in $(UNITS); do rm -f "$(DESTDIR)$(SYSTEMD_USER_DIR)/$$u"; done

check:
	@command -v shellcheck >/dev/null && shellcheck bin/* || echo "shellcheck not installed, skipping"
