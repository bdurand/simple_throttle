# Simple Throttle

[![Continuous Integration](https://github.com/bdurand/simple_throttle/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/simple_throttle/actions/workflows/continuous_integration.yml)
[![Regression Test](https://github.com/bdurand/simple_throttle/actions/workflows/regression_test.yml/badge.svg)](https://github.com/bdurand/simple_throttle/actions/workflows/regression_test.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem provides a very simple throttling mechanism backed by Redis for limiting access to a resource. The throttle can be thought of as a limit on the number of calls in a set time frame (i.e. 100 calls per hour).

## Usage

```ruby
# Initialize Redis client
SimpleThrottle.set_redis(Redis.new)

# ...or provide a block that returns a redis client
SimpleThrottle.set_redis{ connection_pool.redis }

# ...or provide a Redis for a throttle to use
SimpleThrottle.new("user#{user.it}", limit: 10, ttl: 60, redis: Redis.new)

# Add a global throttle (max of 10 requests in 60 seconds)
SimpleThrottle.add(:things, limit: 10, ttl: 60)

# Throttle a global resource
if SimpleThrottle[:things].allowed!
  do_somthing
else
  raise "Too many requests. Resource available in #{SimpleThrottle[:things].wait_time} seconds"
end

# Throttle resource useage per user (100 per hour)
throttle = SimpleThrottle.new("resource@#{current_user.id}", limit: 100, ttl: 3600)
if throttle.allowed!
  do_somthing
else
  raise "Too many requests. Resource available in #{throttle.wait_time} seconds"
end
```

Calling `allowed!` will return `true` if the throttle limit has not yet been reached. If it does return `true`, then it will also start tracking that the call was made (hence the exclamation point syntax). There is no way to release a throttled call (that's why it's called `SimpleThrottle`).

The throttle data is kept in redis as a list of timestamps and will be auto expired if it falls out of use. The thottles time windows are rolling time windows and more calls will be allowed as soon as possible. So, if you have a throttle of, 100 requests per hour, and the throttle kicks in, you will be able to make the next throttled call one hour after the first call being tracked, not one hour after the last call.

You can also increment the throttle yourself with the `increment!` method. This will increment the throttle by the given amount and return the current count. The count will be capped by the throttle limit since excess requests beyond the limit are not tracked in Redis for performance reasons.

```ruby
count = throttle.increment!
if count <= throttle.limit
  do_something
else
  raise "Too many requests: #{count}"
end
```

### Pause to recover option

Throttles can also specify a `pause_to_recover` option set when they are created. When this flag is set, once a throttle check fails, it will continue to fail until the rate at which it is called drops below the maximum rate allowed by the throttle. This is designed for use where you want to detect run away processes constantly hitting a service. Without this set, the process would be able to utilize the resource up to the set limit. With it set, the process would need to pause temporarily to succeed again.

For example, if you have a throttle that allows 10 calls per 60 seconds, then a process hitting every second will succeed 10 times per minute. A similar throttle with the `pause_to_recover` option set, would only succeed on the first 10 calls. After that, it will continue to fail until the rate at which it is called drops below the maximum rate of the throttle (i.e. once every 6 seconds).

```ruby
throttle_1 = SimpleThrottle.new("t1", limit: 10, ttl: 60)
throttle_2 = SimpleThrottle.new("t2", limit: 10, ttl: 60, pause_to_recover: true)

loop do
  if throttle_1.allowed!
    # This will be called 10 times every minute.
    do_thing_1
  end

  if throttle_2.allowed!
    # This will only be called 10 times in total because the throttle is never
    # given a chance to recover.
    do_thing_2
  end
end
```

### Redis requirement

Redis server 2.6 or greater is required for this code.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'simple_throttle'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install simple_throttle
```

## Contributing

Fork the repository and open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
