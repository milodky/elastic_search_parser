# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'elastic_search_parser/version'

Gem::Specification.new do |spec|
  spec.name          = "elastic_search_parser"
  spec.version       = ElasticSearchParser::VERSION
  spec.authors       = ["Xiaoting"]
  spec.email         = ["yext4011@gmail.com"]
  spec.summary       = %q{a light-weight elastic search parser.}
  spec.description   = %q{a light-weight elastic search parser.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_dependency 'memoist'
  spec.add_dependency 'andand'
  spec.add_dependency 'rspec'
  spec.add_dependency 'activesupport'
end
