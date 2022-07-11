# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8

Encoding.default_internal = Encoding::UTF_8

require File.expand_path('lib/vagrant-zones/version', __dir__)

Gem::Specification.new do |spec|
  spec.name          = 'vagrant_zones'
  spec.version       = VagrantPlugins::ProviderZone::VERSION
  spec.authors       = ['Mark Gilbert']
  spec.email         = ['mark.gilbert@prominic.net']
  spec.summary       = 'Vagrant provider plugin to support zones'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/STARTCloud/vagrant-zones'
  spec.license       = 'AGPL-3.0'
  spec.metadata = {
    'rubygems_mfa_required' => 'true',
    'bug_tracker_uri' => 'https://github.com/STARTCloud/issues',
    'changelog_uri' => 'https://github.com/STARTCloud/blob/main/CHANGELOG.md',
    'documentation_uri' => 'http://rubydoc.info/gems/vagrant-zones',
    'source_code_uri' => 'https://github.com/STARTCloud'
  }

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.6.0'
  spec.required_rubygems_version = '>= 1.3.6'
  spec.add_runtime_dependency 'i18n', '~> 1.0'
  spec.add_runtime_dependency 'iniparse', '~> 1.0'
  spec.add_runtime_dependency 'log4r', '~> 1.1'
  spec.add_runtime_dependency 'netaddr', '~> 2.0', '>= 2.0.4'
  spec.add_runtime_dependency 'nokogiri', '<=  1.13.6'
  spec.add_runtime_dependency 'ruby_expect', '~> 1.7', '>= 1.7.5'
  spec.add_development_dependency 'bundler', '~> 2.2', '>= 2.2.25'
  spec.add_development_dependency 'code-scanning-rubocop', '~> 0.5', '>= 0.5.0'
  spec.add_development_dependency 'rake', '~> 13.0', '>= 13.0.6'
  spec.add_development_dependency 'rspec', '~> 3.4'
  spec.add_development_dependency 'rspec-core', '~> 3.4'
  spec.add_development_dependency 'rspec-expectations', '~> 3.10', '>= 3.10.0'
  spec.add_development_dependency 'rspec-mocks', '~> 3.10', '>= 3.10.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'rubocop-rake', '~> 0.6', '>= 0.6.0'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.4', '>= 2.4.0'
  spec.add_development_dependency 'ruby-progressbar', '~> 1.11', '>= 1.11.0'
end
