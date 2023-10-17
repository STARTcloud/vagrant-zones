# frozen_string_literal: true

source 'https://rubygems.org'

group :development do
  # We depend on Vagrant for development, but we don't add it as a
  # gem dependency because we expect to be installed within the
  # Vagrant environment itself using `vagrant plugin`.
  gem 'vagrant', github: 'hashicorp/vagrant', ref: 'v2.4.0'
end

group :plugins do
  gemspec
  gem 'bundler', '~> 2.2', '>= 2.2.3'
  gem 'code-scanning-rubocop', '~> 0.5', '>= 0.5.0'
  gem 'rake', '~> 13.0', '>= 13.0.6'
  gem 'rspec', '~> 3.4'
  gem 'rspec-core', '~> 3.4'
  gem 'rspec-expectations', '~> 3.10', '>= 3.10.0'
  gem 'rspec-mocks', '~> 3.10', '>= 3.10.0'
  gem 'rubocop', '~> 1.0'
  gem 'rubocop-rake', '~> 0.6', '>= 0.6.0'
  gem 'rubocop-rspec', '~> 2.4', '>= 2.4.0'
  gem 'ruby-progressbar', '~> 1.11', '>= 1.11.0'
end
