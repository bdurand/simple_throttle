# frozen_string_literal: true

require "spec_helper"

RSpec.describe SimpleThrottle do
  it "should tell if a call is allowed" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 3, ttl: 0.2)
    other_throttle = SimpleThrottle.new("test_simple_throttle_2", limit: 3, ttl: 0.1, redis: Redis.new)

    expect(throttle.peek).to eq 0
    expect(throttle.allowed!).to eq true
    expect(throttle.peek).to eq 1
    expect(throttle.allowed!).to eq true
    expect(throttle.peek).to eq 2
    expect(throttle.allowed!).to eq true
    expect(throttle.peek).to eq 3
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 3
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 3
    earlier_wait_time = throttle.wait_time
    expect(earlier_wait_time).to be > 0.0
    expect(earlier_wait_time).to be <= throttle.ttl
    expect(earlier_wait_time).to be > throttle.wait_time

    expect(other_throttle.allowed!).to eq true
    expect(other_throttle.peek).to eq 1
    expect(other_throttle.wait_time).to eq 0.0

    sleep(0.3)

    expect(other_throttle.peek).to eq 0
    expect(throttle.allowed!).to eq true
    sleep(0.06)
    expect(throttle.allowed!).to eq true
    sleep(0.06)
    expect(throttle.allowed!).to eq true
    sleep(0.06)
    expect(throttle.allowed!).to eq false
    sleep(0.06)
    expect(throttle.peek).to eq 2
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 3
  end

  it "should increment the throttle" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 5, ttl: 0.2)

    expect(throttle.peek).to eq 0
    expect(throttle.increment!).to eq 1
    expect(throttle.increment!).to eq 2
    expect(throttle.increment!).to eq 3
    expect(throttle.increment!).to eq 4
    expect(throttle.increment!).to eq 5
    expect(throttle.increment!).to eq 6
    expect(throttle.increment!).to eq 6
    expect(throttle.peek).to eq 5
    sleep(0.25)
    expect(throttle.peek).to eq 0
    expect(throttle.increment!).to eq 1
    sleep(0.1)
    expect(throttle.increment!).to eq 2
    sleep(0.1)
    expect(throttle.increment!(2)).to eq 3
    expect(throttle.increment!(2)).to eq 5
    expect(throttle.peek).to eq 5
  end

  it "should track an extra call if pause to recover is set" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 3, ttl: 0.1, pause_to_recover: true)

    expect(throttle.peek).to eq 0
    expect(throttle.allowed!).to eq true
    sleep(0.02)
    expect(throttle.allowed!).to eq true
    sleep(0.02)
    expect(throttle.allowed!).to eq true
    sleep(0.02)
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 4
    sleep(0.02)
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 4
    sleep(0.02)
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 4
    sleep(0.02)
    expect(throttle.allowed!).to eq false
    expect(throttle.peek).to eq 4
    sleep(0.04)
    expect(throttle.allowed!).to eq true
  end

  it "should never return a negative wait_time even when the list holds more than the limit" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 5, ttl: 0.5)
    # increment! can push up to limit + 1 entries, more than `limit`.
    expect(throttle.increment!(10)).to eq 6
    expect(throttle.peek).to eq 6
    wait = throttle.wait_time
    expect(wait).to be >= 0.0
    expect(wait).to be <= throttle.ttl
  end

  it "should use the Redis server clock so local clock skew does not affect peek or wait_time" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 2, ttl: 10)
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq true

    # Skew the local clock an hour ahead; reads use the Redis server clock
    # and should be unaffected.
    allow(Time).to receive(:now).and_return(Time.at(Time.now.to_f + 3600))

    expect(throttle.peek).to eq 2
    wait = throttle.wait_time
    expect(wait).to be > 0.0
    expect(wait).to be <= throttle.ttl
  end

  it "should reject a non-positive increment amount" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 5, ttl: 0.2)
    expect { throttle.increment!(0) }.to raise_error(ArgumentError)
    expect { throttle.increment!(-1) }.to raise_error(ArgumentError)
    expect(throttle.peek).to eq 0
  end

  it "should coerce non-string names to frozen strings" do
    throttle = SimpleThrottle.new(:test_symbol_name, limit: 1, ttl: 1)
    expect(throttle.name).to eq "test_symbol_name"
    expect(throttle.name).to be_frozen

    throttle = SimpleThrottle.new(12345, limit: 1, ttl: 1)
    expect(throttle.name).to eq "12345"
    expect(throttle.name).to be_a(String)
  end

  it "should be able to add global throttles" do
    SimpleThrottle.add(:test_1, limit: 4, ttl: 60)
    SimpleThrottle.add(:test_2, limit: 10, ttl: 3600, redis: Redis.new)
    t1 = SimpleThrottle["test_1"]
    expect(t1.name).to eq "test_1"
    expect(t1.limit).to eq 4
    expect(t1.ttl).to eq 60
    t1 = SimpleThrottle[:test_2]
    expect(t1.name).to eq "test_2"
    expect(t1.limit).to eq 10
    expect(t1.ttl).to eq 3600
  end

  it "should be able to specify the Redis client with a block so it is gotten at runtime" do
    SimpleThrottle.add(:test_3, limit: 4, ttl: 60, redis: lambda { Redis.new })
    SimpleThrottle[:test_3].reset!
    expect(SimpleThrottle[:test_3].peek).to eq 0

    throttle = SimpleThrottle.new(:test_3, limit: 4, ttl: 60, redis: lambda { Redis.new })
    expect(throttle.peek).to eq 0
  end

  it "should work with floats" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 3.8888888888888, ttl: 0.1111111111111111)
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq false
    sleep(0.2)
    expect(throttle.allowed!).to eq true
  end

  it "should deny all requests when the limit is zero" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 0, ttl: 10)
    expect(throttle.allowed!).to eq false
  end

  it "should deny all requests when the limit is less than zero" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: -1, ttl: 10)
    expect(throttle.allowed!).to eq false
  end

  it "should handle the lua script being unloaded by the server" do
    redis = Redis.new
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 3, ttl: 10, redis: redis)
    expect(redis).to receive(:evalsha).and_raise(Redis::CommandError.new("NOSCRIPT"))
    expect(redis).to receive(:evalsha).and_call_original
    expect(throttle.allowed!).to eq true
  end
end
