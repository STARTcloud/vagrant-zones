# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to start a VNC console to the guest
      class VNCConsole < Vagrant.plugin('2', :command)
        def execute
          options = {}
          opts = OptionParser.new do |o|
            o.banner = 'Usage: vagrant zone console vnc [options]'
            o.on('--ip <host_ip>', 'Specify host IP to listen on') do |p|
              options[:ip] = p
            end
            o.on('--port <port>', 'Specify port to listen on') do |p|
              options[:port] = p
            end
            o.on('--detach <yes/no>', 'Run console server in background') do |p|
              options[:detach] = p
            end
            o.on('--kill <yes/no>', 'Kill the previous background console session') do |p|
              options[:kill] = p
            end
          end

          argv = parse_options(opts)
          return unless argv

          unless argv.length <= 4
            @env.ui.info(opts.help)
            return
          end

          options[:port] = nil unless options[:port] =~ /\d/
          with_target_vms(argv, provider: :zone) do |machine|
            driver = machine.provider.driver
            detach = 'yes'
            detach = 'no' unless options[:detach] == 'yes'
            kill = 'yes'
            kill = 'no' unless options[:kill] == 'yes'
            exit = { detach: detach, kill: kill }
            driver.console(@env.ui, 'vnc', options[:ip], options[:port], exit)
          end
        end
      end
    end
  end
end
