# frozen_string_literal: true

require 'log4r'
module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to determine if the VM is created
      class NotCreated
        def initialize(app, _env)
          @app = app
        end

        def call(env)
          env[:ui].info(I18n.t('vagrant_zones.states.not_created'))
          @app.call(env)
        end
      end
    end
  end
end
