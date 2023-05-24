# frozen_string_literal: true

require 'yard'
require 'rubocop/rake_task'
require 'bundler/gem_tasks'

require_relative 'lib/rra'

task default: 'all'

desc 'All'
task all: %i[test yard lint build]

desc 'Run the minitests'
task :test do
  Dir[RRA::Gem.root('test/test*.rb')].sort.each { |f| require f }
end

desc 'Check code notation'
RuboCop::RakeTask.new(:lint) do |task|
  task.patterns = RRA::Gem.files.select { |f| /\A(?:bin.*|Rakefile|.*\.rb)\Z/.match f }
  task.formatters += ['html']
  task.options += ['--fail-level', 'convention', '--out', 'rubocop.html']
end

YARD::Rake::YardocTask.new do |t|
  t.files = RRA::Gem.files
  t.options = ['--no-private', '--protected']
  t.stats_options = ['--list-undoc']
end
