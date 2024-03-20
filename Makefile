
.PHONY: run
run:
	hugo serve -D

.PHONY: build
build:
	@echo "\033[0;32mBuilding rogchap.com...\033[0m\n"
	hugo

.PHONY: publish
publish: build
	@echo "\033[0;32mPublishing updates to GitHub...\033[0m\n"
	@cd public && git add . && git commit -m "rebuilding site - `date`"
	@cd public && git push

.PHONY: post
post:
	@hugo new -k post posts/$(post)
