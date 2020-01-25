# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "simple_throttle"
  spec.version       = File.read(File.expand_path("../VERSION", __FILE__)).chomp
  spec.authors       = ["We Heart It", "Brian Durand"]
  spec.email         = ["dev@weheartit.com", "bbdurand@gmail.com"]
  spec.summary       = "Simple redis backed throttling mechanism to limit access to a resource"
  spec.description   = "Simple redis backed throttling mechanism to limit access to a resource."
  spec.homepage      = "https://github.com/weheartit/simple_throttle"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency('redis')

  spec.add_development_dependency "bundler", ">= 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
