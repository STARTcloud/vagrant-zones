# frozen_string_literal: true

require 'log4r'
require 'securerandom'
require 'digest/md5'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is use to define the network
      class MessageNotCreated
        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action')
          @app = app
        end

        def call(env)
          env[:ui].info I18n.t('vagrant_zones.vm_not_created')
          @app.call(env)
        end
      end
    end
  end
end
