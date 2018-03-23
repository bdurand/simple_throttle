This gem provides a very simple throttling mechanism backed by redis for limiting access to a resource. The throttle can be thought of as a limit on the number of calls in a set time frame (i.e. 100 calls per hour). These

## Usage

```ruby
# Initialize Redis client
SimpleThrottle.set_redis(Redis.new)

# ...or provide a block that returns a redis client
SimpleThrottle.set_redis{ connection_pool.redis }

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

Redis server 2.6 or greater is required.