# `make check` tests the HEAD commit (never the working copy) in the job image,
# as CI does, and leaves a passing entry per job that the pre-push hook signs
# as a local record. It needs Docker and git, nothing else. Name fewer jobs
# with `make check JOBS=web`.
JOBS ?= api web kit

.PHONY: check
check:
	bash ci/kit/bin/local-ci run --commit HEAD $(JOBS)
