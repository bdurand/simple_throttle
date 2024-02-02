# frozen_string_literal: true

require "redis"

# Create a simple throttle that can be used to limit the number of request for a resouce
# per time period. These objects are thread safe.
class SimpleThrottle
  # Server side Lua script that maintains the throttle in redis. The throttle is stored as a list
  # of timestamps in milliseconds. When the script is invoked it will scan the oldest entries
  # removing any that should be expired from the list. If the list is below the specified limit
  # then the current entry will be added. The list is marked to expire with the oldest entry so
  # there's no need to cleanup the lists.
  LUA_SCRIPT = <<~LUA
    local list_key = KEYS[1]
    local limit = tonumber(ARGV[1])
    local ttl = tonumber(ARGV[2])
    local now = ARGV[3]
    local pause_to_recover = tonumber(ARGV[4])
    local amount = tonumber(ARGV[5])
    local cleanup = tonumber(ARGV[6])

    local size = redis.call('llen', list_key)
    if size >= limit or (cleanup > 0 and size > 0) then
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

    if pause_to_recover > 0 then
      limit = limit + 1
    end

    if size + amount > limit then
      amount = (limit - size) + 1
    end

    if size < limit then
      for i = 1, amount do
        redis.call('rpush', list_key, now)
      end
      redis.call('pexpire', list_key, ttl)
    end

    return size + amount
  LUA

  @lock = Mutex.new

  class << self
    # Add a global throttle that can be referenced later with the [] method.
    # This can be used to configure global throttles that you want to setup once
    # and then use in multiple places.
    #
    # @param name [String] unique name for the throttle
    # @param ttl [Numeric] number of seconds that the throttle will remain active
    # @param limit [Integer] number of allowed requests within the throttle ttl
    # @param pause_to_recover [Boolean] require processes calling the throttle
    #   to pause at least temporarily before freeing up the throttle. If this is true,
    #   then a throttle called constantly with no pauses will never free up.
    # @param redis [Redis, Proc] Redis instance to use or a Proc that yields a Redos instance
    # @return [void]
    def add(name, ttl:, limit:, pause_to_recover: false, redis: nil)
      @lock.synchronize do
        @throttles ||= {}
        @throttles[name.to_s] = new(name, limit: limit, ttl: ttl, pause_to_recover: pause_to_recover, redis: redis)
      end
    end

    # Returns a globally defined throttle with the specfied name.
    #
    # @param name [String, Symbol] name of the throttle
    # @return [SimpleThrottle]
    def [](name)
      if defined?(@throttles) && @throttles
        @throttles[name.to_s]
      end
    end

    # Set the Redis instance to use for maintaining the throttle. This can either be set
    # with a hard coded value or by the value yielded by a block. If the block form is used
    # it will be invoked at runtime to get the instance. Use this method if your Redis instance
    # isn't constant (for example if you're in a forking environment and re-initialize connections
    # on fork)
    #
    # @param client [Redis, Proc]
    # @yieldreturn [Redis]
    # @return [void]
    def set_redis(client = nil, &block)
      @redis_client = (client || block) # rubocop:disable Style/RedundantParentheses
    end

    # Return the Redis instance where the throttles are stored.
    #
    # @return [Redis]
    def redis
      @redis_client ||= Redis.new
      if @redis_client.is_a?(Proc)
        @redis_client.call
      else
        @redis_client
      end
    end

    private

    def execute_lua_script(redis:, keys:, args:)
      client = redis
      @script_sha_1 ||= client.script(:load, LUA_SCRIPT)
      attempts = 0

      begin
        client.evalsha(@script_sha_1, Array(keys), Array(args))
      rescue Redis::CommandError => e
        if e.message.include?("NOSCRIPT") && attempts < 2
          @script_sha_1 = client.script(:load, LUA_SCRIPT)
          attempts += 1
          retry
        else
          raise e
        end
      end
    end
  end

  attr_reader :name, :limit, :ttl

  # Create a new throttle.
  #
  # @param name [String] unique name for the throttle
  # @param ttl [Numeric] number of seconds that the throttle will remain active
  # @param limit [Integer] number of allowed requests within the throttle ttl
  # @param pause_to_recover [Boolean] require processes calling the throttle
  #   to pause at least temporarily before freeing up the throttle. If this is true,
  #   then a throttle called constantly with no pauses will never free up.
  # @param redis [Redis, Proc] Redis instance to use or a Proc that yields a Redos instance
  def initialize(name, ttl:, limit:, pause_to_recover: false, redis: nil)
    @name = name.to_s
    @name = name.dup.freeze unless name.frozen?
    @limit = limit.to_i
    @ttl = ttl.to_f
    @pause_to_recover = !!pause_to_recover
    @redis = redis
  end

  # Returns true if the limit for the throttle has not been reached yet. This method
  # will also track the throttled resource as having been invoked on each call.
  #
  # @return [Boolean]
  def allowed!
    size = add_request(1, false)
    size <= limit
  end

  # Increment the throttle by the specified and return the current size. Because
  # how the throttle is implemented in Redis, the return value will always max
  # out at the throttle limit + 1 or, if the pause to recover option is set, limit + 2.
  #
  # @param amount [Integer] amount to increment the throttle by
  # @return [Integer]
  def increment!(amount = 1)
    add_request(amount, true)
  end

  # Reset a throttle back to zero.
  #
  # @return [void]
  def reset!
    redis_client.del(redis_key)
  end

  # Peek at the current number for throttled calls being tracked.
  #
  # @return [Integer]
  def peek
    timestamps = redis_client.lrange(redis_key, 0, -1).collect(&:to_i)
    min_timestamp = ((Time.now.to_f - ttl) * 1000).ceil
    timestamps.count { |t| t > min_timestamp }
  end

  # Returns when the next resource call should be allowed. Note that this doesn't guarantee that
  # calling allow! will return true if the wait time is zero since other processes or threads can
  # claim the resource.
  #
  # @return [Float]
  def wait_time
    if peek < limit
      0.0
    else
      first = redis_client.lindex(redis_key, 0).to_f / 1000.0
      delta = Time.now.to_f - first
      delta = 0.0 if delta < 0
      ttl - delta
    end
  end

  private

  def redis_client
    if @redis.is_a?(Proc)
      @redis.call || self.class.redis
    else
      @redis || self.class.redis
    end
  end

  def redis_key
    "simple_throttle.#{name}"
  end

  def add_request(amount, cleanup)
    pause_to_recover_arg = (@pause_to_recover ? 1 : 0)
    time_ms = (Time.now.to_f * 1000).round
    ttl_ms = (ttl * 1000).ceil
    self.class.send(
      :execute_lua_script,
      redis: redis_client,
      keys: [redis_key],
      args: [limit, ttl_ms, time_ms, pause_to_recover_arg, amount, (cleanup ? 1 : 0)]
    )
  end
end
