require "bundler/gem_tasks"

desc 'Default: run unit tests.'
task :default => :test

desc 'RVM likes to call it tests'
task :tests => :test

begin
  require 'rspec'
  require 'rspec/core/rake_task'
  desc 'Run the unit tests'
  RSpec::Core::RakeTask.new(:test)
rescue LoadError
  task :test do
    STDERR.puts "You must have rspec 2.0 installed to run the tests"
  end
end
