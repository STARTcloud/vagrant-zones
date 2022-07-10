# frozen_string_literal: true

require 'log4r'
require 'securerandom'
require 'digest/md5'

module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to prepare NFS ids for NFS Sharing
      class PrepareNFSValidIds
        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::prepare_nfs_valid_ids')
          @app = app
        end

        def call(env)
          env[:nfs_valid_ids] = [env[:machine].id]
          @app.call(env)
        end
      end
    end
  end
end
