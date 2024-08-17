# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to start a console to the zone via WebVNC, VNC or Serial/Telnet
      class Console < Vagrant.plugin('2', :command)
        def initialize(argv, env)
          @main_args, @sub_command, @sub_args = split_main_and_subcommand(argv)

          @subcommands = Vagrant::Registry.new
          @subcommands.register(:vnc) do
            require File.expand_path('vnc_console', __dir__)
            VNCConsole
          end
          @subcommands.register(:zlogin) do
            require File.expand_path('zlogin_console', __dir__)
            ZloginConsole
          end
          @subcommands.register(:webvnc) do
            require File.expand_path('webvnc_console', __dir__)
            WebVNCConsole
          end
          super
        end

        def execute
          if @main_args.include?('-h') || @main_args.include?('--help')
            # Print the help for all the vagrant-zones commands.
            return help
          end

          with_target_vms(@main_args, provider: :zone) do |machine|
            @sub_command = machine.provider_config.console.to_sym unless machine.provider_config.console.nil? || @sub_command
            command_class = @subcommands.get(@sub_command.to_sym) if @sub_command
            @logger.debug("Invoking command class: #{command_class} #{machine.provider_config.console.to_sym}")
            return help if !command_class || !@sub_command

            # Initialize and execute the command class
            command_class.new(@sub_args, @env).execute
          end
        end

        def help
          opts = OptionParser.new do |subopts|
            subopts.banner = 'Usage: vagrant zone console <subcommand> [<args>]'
            subopts.separator ''
            subopts.separator 'Available subcommands:'
            # Add the available subcommands as separators in order to print them
            # out as well.
            keys = @subcommands.map { |(key, _value)| key.to_s }.sort
            keys.each do |key|
              subopts.separator "     #{key}"
            end
            subopts.separator 'For help on any individual subcommand run `vagrant zone console <subcommand> -h`'
          end
          @env.ui.info(opts.help, :prefix => false)
        end
      end
    end
  end
end
