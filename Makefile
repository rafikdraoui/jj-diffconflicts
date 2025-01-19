help:
	@echo "Available targets:"
	@echo "test             Run tests"
	@echo "conflicts        Generate example conflicts in test repository"

test:
	@TEST=1 nvim --headless --noplugin -l scripts/run_tests.lua

conflicts:
	@./scripts/make-conflicts.sh
