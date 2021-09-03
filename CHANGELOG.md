# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.2

### Added
- Throttle insances can now specify the Redis instance to override the global setting
- Redis instance now defaults to the default redis instance: `Redis.new`
- Optimize loading LUA script to Redis; now done globally instead of per throttle instance


## 1.0.1

### Added
- Added mutex in `SimpleThrottle.add` to ensure thread safety when adding global throttles.


## 1.0.0

### Added
- Simple Redis backed throttle for Ruby.
