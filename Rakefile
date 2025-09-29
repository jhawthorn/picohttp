# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "rake/extensiontask"

task build: :compile

GEMSPEC = Gem::Specification.load("picohttp.gemspec")

Rake::ExtensionTask.new("picohttp", GEMSPEC) do |ext|
  ext.lib_dir = "lib/picohttp"
end

task default: %i[clobber compile test]
