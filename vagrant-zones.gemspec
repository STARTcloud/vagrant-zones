# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8

require File.expand_path('lib/vagrant-zones/version', __dir__)

Gem::Specification.new do |spec|
  spec.name          = 'vagrant-zones'
  spec.version       = VagrantPlugins::ProviderZone::VERSION
  spec.authors       = ['Mark Gilbert']
  spec.email         = ['support@prominic.net']
  spec.summary       = 'Vagrant provider plugin to support zones'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/STARTCloud/vagrant-zones'
  spec.license       = 'AGPL-3.0'
  spec.metadata = {
    'rubygems_mfa_required' => 'true',
    'bug_tracker_uri' => 'https://github.com/STARTcloud/vagrant-zones/issues',
    'changelog_uri' => 'https://github.com/STARTcloud/vagrant-zones/blob/main/CHANGELOG.md',
    'documentation_uri' => 'http://rubydoc.info/gems/vagrant-zones',
    'source_code_uri' => 'https://github.com/STARTCloud/vagrant-zones',
    'github_repo' => 'https://github.com/STARTCloud/vagrant-zones'
  }

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.7.0'
  spec.required_rubygems_version = '>= 1.3.6'
  spec.add_dependency  'i18n', '~> 1.0'
  spec.add_dependency  'iniparse', '~> 1.0'
  spec.add_dependency  'log4r', '~> 1.1'
  spec.add_dependency  'netaddr', '~> 2.0', '>= 2.0.4'
  spec.add_dependency  'ruby_expect', '~> 1.7', '>= 1.7.5'
end
