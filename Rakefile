# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'net/ssh'

# Immediately sync all stdout so that tools like buildbot can
# immediately load in the output.
$stdout.sync = true
$stderr.sync = true

# Change to the directory of this file.
Dir.chdir(File.expand_path(__dir__))

# This installs the tasks that help with gem creation and
# publishing.
Bundler::GemHelper.install_tasks

# Install the `spec` task so that we can run tests.
RSpec::Core::RakeTask.new

# Install the `rubocop` task
RuboCop::RakeTask.new

RuboCop::RakeTask.new(:rubocoplayout) do |t|
  t.options = ['--auto-correct --only ']
end

# Default task is to run the unit tests
task default: %w[rubocop spec]
