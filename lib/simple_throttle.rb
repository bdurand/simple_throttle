require 'redis'
require 'thread'

# Create a simple throttle that can be used to limit the number of request for a resouce
# per time period. These objects are thread safe.
class SimpleThrottle
  
  @@lock = Mutex.new
  
  class << self
    # Add a global throttle that can be referenced later with the [] method.
    def add(name, limit:, ttl:)
      @@lock.synchronize do
        @throttles ||= {} 
        @throttles[name.to_s] = new(name, limit: limit, ttl: ttl)     
      end  
    end
    
    # Returns a globally defined throttle with the specfied name.
    def [](name)
      if defined?(@throttles) && @throttles
        @throttles[name.to_s]
      else
        nil
      end
    end
    
    # Set the Redis instance to use for maintaining the throttle. This can either be set
    # with a hard coded value or by the value yielded by a block. If the block form is used
    # it will be invoked at runtime to get the instance. Use this method if your Redis instance
    # isn't constant (for example if you're in a forking environment and re-initialize connections
    # on fork)
    def set_redis(client = nil, &block)
      @redis_client = (client || block)
    end
    
    # Return the Redis instance where the throttles are stored.
    def redis
      if @redis_client.is_a?(Proc)
        @redis_client.call
      else
        @redis_client
      end
    end
  end
  
  attr_reader :name, :limit, :ttl
  
  # Create a new throttle with the given name. The ttl argument specifies the time
  # range that is being used for measuring in seconds while the limit specifies how
  # many calls are allowed in that range.
  def initialize(name, limit:, ttl:)
    @name = name.to_s
    @name.freeze unless @name.frozen?
    @limit = limit
    @ttl = ttl
    @script_sha_1 = nil
  end
  
  # Returns true if the limit for the throttle has not been reached yet. This method
  # will also track the throttled resource as having been invoked on each call.
  def allowed!
    size = current_size(true)
    if size < limit
      true
    else
      false
    end
  end
  
  # Reset a throttle back to zero.
  def reset!
    self.class.redis.del(redis_key)
  end
  
  # Peek at the current number for throttled calls being tracked.
  def peek
    current_size(false)
  end
  
  # Returns when the next resource call should be allowed. Note that this doesn't guarantee that
  # calling allow! will return true if the wait time is zero since other processes or threads can
  # claim the resource.
  def wait_time
    if peek < limit
      0.0
    else
      first = self.class.redis.lindex(redis_key, 0).to_f / 1000.0
      delta = Time.now.to_f - first
      delta = 0.0 if delta < 0
      delta
    end
  end
    
  private
  
  # Evaluate and execute a Lua script on the redis server that returns the number calls currently being tracked.
  # If push is set to true then a new item will be added to the list.
  def current_size(push)
    redis = self.class.redis
    @script_sha_1 ||= redis.script(:load, lua_script)
    begin
      push_arg = (push ? 1 : 0)
      time_ms = (Time.now.to_f * 1000).round
      ttl_ms = ttl * 1000
      redis.evalsha(@script_sha_1, [], [redis_key, limit, ttl_ms, time_ms, push_arg])
    rescue Redis::CommandError => e
      if e.message.include?('NOSCRIPT'.freeze)
        @script_sha_1 = redis.script(:load, lua_script)
        retry
      else
        raise e
      end
    end
  end
  
  def redis_key
    "simple_throttle.#{name}"
  end
  
  # Server side Lua script that maintains the throttle in redis. The throttle is stored as a list
  # of timestamps in milliseconds. When the script is invoked it will scan the oldest entries
  # removing any that should be expired from the list. If the list is below the specified limit
  # then the current entry will be added. The list is marked to expire with the oldest entry so
  # there's no need to cleanup the lists.
  def lua_script
    <<-LUA
    local list_key = ARGV[1]
    local limit = tonumber(ARGV[2])
    local ttl = tonumber(ARGV[3])
    local now = ARGV[4]
    local push = tonumber(ARGV[5])
    
    local size = redis.call('llen', list_key)
    if size >= limit then
      local expired = tonumber(now) - ttl
      while size > 0 do
        local t = redis.call('lpop', list_key)
        if tonumber(t) > expired then
          redis.call('lpush', list_key, t)
          break
        end
        size = size - 1
      end
    end

    if push > 0 and size < limit then
      redis.call('rpush', list_key, now)
      redis.call('pexpire', list_key, ttl)
    end
    
    return size
    LUA
  end
end
