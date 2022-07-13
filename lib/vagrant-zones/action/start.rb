# frozen_string_literal: true

require 'log4r'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to start the zone
      class Start
        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::import')
          @app = app
        end

        def call(env)
          @machine = env[:machine]
          @driver  = @machine.provider.driver
          @driver.check_zone_support(env[:ui])
          @driver.boot(env[:ui])
          @app.call(env)
        end
      end
    end
  end
end
