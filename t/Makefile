#! /usr/bin/make -f

TARGETS=unit_test.flow init_test.flow commons-cli.flow
TARGETS2=$(TARGETS:.flow=.2.flow)
.PHONY: all check test clean

all: check
check: test $(TARGETS) $(TARGETS2)
	set -e; for f in $(TARGETS:.flow=); do \
		diff -u $$f.flow $$f.2.flow; \
	done
test:
	prove -l javacgflow.t
	perlcritic javacgflow.t
clean:
	rm -f $(TARGETS) $(TARGETS2)

%.flow: %.javacg-static
	../javacgflow.pl $< >$@
%.2.flow: %.javacg-static
	../javacgflow.pl $< >$@
