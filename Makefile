#! /usr/bin/make -f

SCRIPTS=javacgflow.pl
MANUALS=javacgflow.pl.1
TARGETS=README.md $(MANUALS)

PREFIX=$(HOME)/.local
bindir=$(PREFIX)/bin
mandir=$(PREFIX)/man
man1dir=$(mandir)/man1

.PHONY: all check clean install uninstall

all: $(TARGETS)
README.md: $(SCRIPTS)
	pod2markdown $(SCRIPTS) > README.md
check:
	cd t && make check
	perlcritic $(SCRIPTS)
	podchecker $(SCRIPTS)
clean:
	rm -f $(TARGETS)
	cd t && make clean
install: $(MANUALS)
	install -d $(DESTDIR)$(bindir) $(DESTDIR)$(man1dir)
	install -m 644 $(MANUALS) $(DESTDIR)$(man1dir)
	install -m 755 $(SCRIPTS) $(DESTDIR)$(bindir)
uninstall:
	cd $(DESTDIR)$(man1dir) && rm -f $(MANUALS)
	cd $(DESTDIR)$(bindir) && rm -f $(SCRIPTS)

%.1: %
	pod2man $< > $@
