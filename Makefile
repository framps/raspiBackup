.PHONY: test

test:
	@echo "*** test_version ***"
	@test/test_version.sh
	@echo
	@echo "*** test_help ***"
	@test/test_help.sh
	@echo
	@echo "*** test_dryrun ***"
	@test/test_dryrun.sh
	@echo

