# frozen_string_literal: true

require 'pathname'

module VagrantPlugins
  # This is used to configure, manage, create and destroy zones where vagrant by itself cannot
  module ProviderZone
    lib_path = Pathname.new(File.expand_path('vagrant-zones', __dir__))
    autoload :Action, lib_path.join('action')
    autoload :Executor, lib_path.join('executor')
    autoload :Driver, lib_path.join('driver')
    autoload :Errors, lib_path.join('errors')
    # This function returns the path to the source of this plugin
    # @return [Pathname]
    def self.source_root
      @source_root ||= Pathname.new(File.expand_path('..', __dir__))
    end
  end
end

begin
  require 'vagrant'
rescue LoadError
  raise 'The Vagrant vagrant-zones plugin must be run within Vagrant.'
end

raise 'The Vagrant vagrant-zones plugin is only compatible with Vagrant 2+.' if Vagrant::VERSION < '2'

require 'vagrant/zones/plugin'
