# -*- encoding: utf-8 -*-
require File.expand_path('../lib/macabee/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jason May"]
  gem.email         = ["jmay@pobox.com"]
  gem.description   = %q{Move updates in and out of MacOSX Address Book}
  gem.summary       = %q{Move updates in and out of MacOSX Address Book}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "macabee"
  gem.require_paths = ["lib"]
  gem.version       = Macabee::VERSION

  # gem.add_dependency 'hashdiff'

  gem.add_development_dependency "rake", "~> 0.9.2"
  gem.add_development_dependency "rspec", "~> 2.9.0"
  gem.add_development_dependency "guard-rspec", "~> 0.7.0"
  gem.add_development_dependency "ruby_gntp", "~> 0.3.4"
end
