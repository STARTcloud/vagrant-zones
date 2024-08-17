# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to manage the power controls for the zone
      class GuestPowerControls < Vagrant.plugin('2', :command)
        def initialize(argv, env)
          @main_args, @sub_command, @sub_args = split_main_and_subcommand(argv)

          @subcommands = Vagrant::Registry.new
          @subcommands.register(:restart) do
            require File.expand_path('restart_guest', __dir__)
            RestartGuest
          end
          @subcommands.register(:shutdown) do
            require File.expand_path('shutdown_guest', __dir__)
            ShutdownGuest
          end
          super
        end

        def execute
          if @main_args.include?('-h') || @main_args.include?('--help')
            # Print the help for all the vagrant-zones commands.
            return help
          end

          command_class = @subcommands.get(@sub_command.to_sym) if @sub_command
          return help if !command_class || !@sub_command

          @logger.debug("Invoking command class: #{command_class} #{@sub_args.inspect}")

          # Initialize and execute the command class
          command_class.new(@sub_args, @env).execute
        end

        def help
          opts = OptionParser.new do |subopts|
            subopts.banner = 'Usage: vagrant zone control <subcommand> [<args>]'
            subopts.separator ''
            subopts.separator 'Available subcommands:'
            # Add the available subcommands as separators in order to print them
            # out as well.
            keys = @subcommands.map { |(key, _value)| key.to_s }.sort
            keys.each do |key|
              subopts.separator "     #{key}"
            end
            subopts.separator ''
            subopts.separator 'For help on any individual subcommand run `vagrant zone control <subcommand> -h`'
          end
          @env.ui.info(opts.help, :prefix => false)
        end
      end
    end
  end
end
