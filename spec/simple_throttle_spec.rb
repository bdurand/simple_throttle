# frozen_string_literal: true

require_relative "spec_helper"

describe SimpleThrottle do
  it "should tell if a call is allowed" do
    throttle = SimpleThrottle.new("test_simple_throttle", limit: 3, ttl: 1)
    throttle.reset!
    other_throttle = SimpleThrottle.new("test_simple_throttle_2", limit: 3, ttl: 1, redis: Redis.new)
    other_throttle.reset!

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
    wait_time = throttle.wait_time
    expect(wait_time).to be > 0.0
    expect(wait_time).to be <= 1.0

    expect(other_throttle.allowed!).to eq true
    expect(other_throttle.peek).to eq 1
    expect(other_throttle.wait_time).to eq 0.0

    sleep(1.1)

    expect(throttle.allowed!).to eq true
    sleep(0.3)
    expect(throttle.allowed!).to eq true
    sleep(0.3)
    expect(throttle.allowed!).to eq true
    sleep(0.3)
    expect(throttle.allowed!).to eq false
    sleep(0.3)
    expect(throttle.allowed!).to eq true
    expect(throttle.allowed!).to eq false
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
    SimpleThrottle.add(:test_1, limit: 4, ttl: 60, redis: lambda { Redis.new })
    SimpleThrottle["test_1"].reset!
    expect(SimpleThrottle["test_1"].peek).to eq 0

    throttle = SimpleThrottle.new(:test_1, limit: 4, ttl: 60, redis: lambda { Redis.new })
    expect(SimpleThrottle["test_1"].peek).to eq 0
  end
end
