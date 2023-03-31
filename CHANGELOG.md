# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.7

## Fixed
- Fixed peek method to return the correct value rather than the raw value from Redis.
### Changed
- Updated repository location and gem owners

## 1.0.6

### Added
- Add support for `pause_to_recover` flag on throttles to force calls to the throttle to fail until the process calling them has paused temporarily.

## 1.0.5

### Added
- Make loading lua script play better with Redis clusters.
- Handle failures loading lua script on Redis server to prevent infinite loop.

## 1.0.4

### Fixed
- Fix wait_time method to match the documentation from [bc-swoop](https://github.com/bc-swoop)

## 1.0.3

### Changed
- Ensure that arguments sent to Redis Lua script are cast to integers.

## 1.0.2

### Added
- Throttle insances can now specify the Redis instance to override the global setting.
- Redis instance now defaults to the default redis instance: `Redis.new`.
- Optimize loading LUA script to Redis; now done globally instead of per throttle instance.


## 1.0.1

### Added
- Added mutex in `SimpleThrottle.add` to ensure thread safety when adding global throttles.


## 1.0.0

### Added
- Simple Redis backed throttle for Ruby.
