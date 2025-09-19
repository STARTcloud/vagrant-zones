# frozen_string_literal: true

require 'log4r'
require 'vagrant-zones/util/timer'
require 'vagrant/util/retryable'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to shutdown the zone
      class Shutdown
        include Vagrant::Util::Retryable

        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::shutdown')
          @app = app
        end

        def call(env)
          @machine = env[:machine]
          @driver  = @machine.provider.driver
          ui = env[:ui]
          ui.info(I18n.t('vagrant_zones.graceful_shutdown_started'))
          @driver.control(ui, 'shutdown')
          env[:metrics] ||= {}
          env[:metrics]['instance_ssh_time'] = Util::Timer.time do
            retryable(on: Errors::TimeoutError, tries: 300) do
              # If we're interrupted don't worry about waiting
              break if env[:interrupted]
              break unless env[:machine].communicate.ready?
            end
          end
          env[:metrics]['instance_ssh_time'] = Util::Timer.time do
            300.times do
              state_id = @driver.state(@machine)
              ui.info(I18n.t('vagrant_zones.graceful_shutdown_complete')) unless state_id == :running
              sleep 1 if state_id == :running
              break unless state_id == :running
              break if env[:interrupted]
            end
          end
          @driver.halt(env[:ui])
          @app.call(env)
        end
      end
    end
  end
end
