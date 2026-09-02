FLUTTER ?= flutter
DART ?= dart

.PHONY: format analyze test check run

format:
	$(DART) format lib test

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

check: format analyze test

run:
	$(FLUTTER) run
