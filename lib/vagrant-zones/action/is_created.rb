# frozen_string_literal: true

require 'log4r'
module VagrantPlugins
  module ProviderZone
    module Action
      # This can be used with 'Call' built-in to check if the machine
      # is created and branch in the middleware.
      class IsCreated
        def initialize(app, _env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_zones::action')
        end

        def call(env)
          env[:result] = env[:machine].state.id != :not_created
          @app.call(env)
        end
      end
    end
  end
end
