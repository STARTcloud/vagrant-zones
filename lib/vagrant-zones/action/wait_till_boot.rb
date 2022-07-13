# frozen_string_literal: true

require 'log4r'
require 'vagrant-zones/util/timer'
require 'vagrant/util/retryable'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is used wait till the zone is booted
      class WaitTillBoot
        include Vagrant::Util::Retryable

        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::import')
          @app = app
        end

        def terminate(env)
          return unless env[:machine].state.id != :not_created

          # If we're not supposed to destroy on error then just return
          return unless env[:destroy_on_error]

          if env[:halt_on_error]
            halt_env = env.dup
            halt_env.delete(:interrupted)
            halt_env[:config_validate] = false
            env[:action_runner].run(Action.action_halt, halt_env)
          else
            destroy_env = env.dup
            destroy_env.delete(:interrupted)
            destroy_env[:config_validate] = false
            destroy_env[:force_confirm_destroy] = true
            env[:action_runner].run(Action.action_destroy, destroy_env)
          end
        end

        def call(env)
          @machine = env[:machine]
          @driver  = @machine.provider.driver
          ui = env[:ui]
          # Initialize metrics if they haven't been
          env[:metrics] ||= {}
          env[:metrics]['instance_boot_time'] = Util::Timer.time do
            next if env[:interrupted]

            breakwait = @driver.waitforboot(ui, env[:metrics], env[:interrupted])
            ui.info(I18n.t('vagrant_zones.boot_ready') + " in #{env[:metrics]['instance_boot_time']} Seconds") if breakwait
            break if breakwait
          end
          return terminate(env) if env[:interrupted]

          @app.call(env)
        end
      end
    end
  end
end
