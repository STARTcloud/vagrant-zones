# frozen_string_literal: true

require 'log4r'
require 'vagrant-zones/util/timer'
require 'vagrant/util/retryable'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to restart the zone
      class Restart
        include Vagrant::Util::Retryable

        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::restart')
          @app = app
        end

        def call(env)
          @machine = env[:machine]
          @driver = @machine.provider.driver
          ui = env[:ui]
          ui.info(I18n.t('vagrant_zones.graceful_restart'))
          @driver.control(ui, 'restart')

          env[:metrics] ||= {}
          env[:metrics]['instance_ssh_time'] = Util::Timer.time do
            retryable(on: Errors::TimeoutError, tries: 300) do
              # If we're interrupted don't worry about waiting
              next if env[:interrupted]

              loop do
                break if env[:interrupted]
                break unless env[:machine].communicate.ready?
              end
            end
          end

          ui.info(I18n.t('vagrant_zones.zone_gracefully_stopped_waiting_for_boot'))
          env[:metrics] ||= {}
          env[:metrics]['instance_ssh_time'] = Util::Timer.time do
            retryable(on: Errors::TimeoutError, tries: 300) do
              # If we're interrupted don't worry about waiting
              next if env[:interrupted]
              break if env[:machine].communicate.ready?
            end
          end
          ui.info(I18n.t('vagrant_zones.zone_gracefully_restarted'))
          @app.call(env)
        end
      end
    end
  end
end
