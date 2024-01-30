begin
  require "bundler/setup"
rescue LoadError
  puts "You must `gem install bundler` and `bundle install` to run rake tasks"
end

require "yard"
YARD::Rake::YardocTask.new(:yard)

require "bundler/gem_tasks"

task :release do
  unless `git rev-parse --abbrev-ref HEAD`.chomp == "master"
    warn "Gem can only be released from the master branch"
    exit 1
  end
end

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

require "standard/rake"
