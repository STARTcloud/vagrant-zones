# frozen_string_literal: true

require 'log4r'
require 'securerandom'
require 'digest/md5'

module VagrantPlugins
  module ProviderZone
    module Action
      # This will create the zone
      class Create
        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::import')
          @app = app
        end

        def call(env)
          @machine = env[:machine]
          @driver  = @machine.provider.driver
          @machine.id = SecureRandom.uuid
          @driver.create_dataset(env[:ui])
          @driver.zonecfg(env[:ui])
          @driver.install(env[:ui])
          @app.call(env)
        end
      end
    end
  end
end
