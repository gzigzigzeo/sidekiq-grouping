lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sidekiq/grouping/version"

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-grouping"
  spec.version       = Sidekiq::Grouping::VERSION
  spec.authors       = ["Victor Sokolov"]
  spec.email         = ["gzigzigzeo@gmail.com"]
  spec.summary       = %q(
    Allows identical sidekiq jobs to be processed with a single background call
  )
  spec.homepage      = "http://github.com/gzigzigzeo/sidekiq-grouping"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "rspec-sidekiq"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "byebug"

  spec.add_dependency "activesupport"
  spec.add_dependency "sidekiq", ">= 3.4.2"
  spec.add_dependency "concurrent-ruby"
end
