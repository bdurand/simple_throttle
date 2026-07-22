# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

begin
  require "simplecov"
  SimpleCov.start do
    skip ["/spec/"]
  end
rescue LoadError
end

Bundler.require(:default, :test)

require_relative "../lib/simple_throttle"

redis = Redis.new
SimpleThrottle.set_redis(redis)

RSpec.configure do |config|
  config.warnings = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.before do
    redis.flushdb
  end
end
