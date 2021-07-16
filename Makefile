all: submodules ruby brew gems

submodules:
	git submodule update

ruby: .ruby-version
	rbenv install -s

brew: Brewfile
	brew bundle --no-lock

gems: Gemfile Gemfile.lock
	bundle install

lint: ruby gems brew .FORCE
	bundle exec rubocop
	swiftlint --quiet

danger: lint .FORCE
	danger-swift ci

start_server: submodules stop_server .FORCE
	$(SHELL) Scripts/startServer.sh

stop_server: .FORCE
	$(SHELL) Scripts/stopServer.sh

tests: submodules ruby gems brew start_server .FORCE
	$(SHELL) Scripts/runTests.sh
	$(MAKE) stop_server

unit_tests: submodules ruby gems brew .FORCE
	bundle exec fastlane tests test_plan:'UnitTests'

translations: gems .FORCE
	bundle exec fastlane translations

pr: .FORCE
	bundle exec fastlane pr

deployAdHoc: lint .FORCE
	bundle exec fastlane deployAdHoc ci:$(CI)

preview: lint .FORCE
	bundle exec fastlane preview version:$(VERSION) skip_increment_build_number:$(SKIP_INCREMENT_BUILD_NUMBER)

release: lint .FORCE
	bundle exec fastlane release

.FORCE:
