This gem provides a very simple throttling mechanism backed by redis for limiting access to a resource.

## Usage

```ruby
# Initialize Redis client
SimpleThrottle.set_redis(Redis.new)

# Add a global throttle (max of 10 requests in 60 seconds)
SimpleThrottle.add(:things, limit: 10, ttl: 60)

# Throttle a resource
if SimpleThrottle[:things].allowed!
  do_somthing
else
  raise "Too many requests. Resource available in #{SimpleThrottle[:things].wait_time} seconds"
end
```

Calling `allow!` will return true if the throttle limit has not yet been reached and will also start tracking a new call if it returned true. There is no way to release a throttled call (that's why it's called SimpleThrottle).

The throttle data is kept in redis as a list of timestamps and will be auto expired if it falls out of use. The thottles time windows are rolling time windows and more calls will be allowed as soon as possible.

Redis server 2.6 or greater is required.