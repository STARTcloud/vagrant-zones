# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to restart the guest from inside the guest
      class RestartGuest < Vagrant.plugin('2', :command)
        def execute
          opts = OptionParser.new do |o|
            o.banner = 'Usage: vagrant zone control restart [options]'
          end

          argv = parse_options(opts)
          return unless argv

          unless argv.empty?
            @env.ui.info(opts.help)
            return
          end

          ## Wait for VM up
          with_target_vms(argv, provider: :zone) do |machine|
            machine.action('restart')
          end
        end
      end
    end
  end
end
