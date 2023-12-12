# frozen_string_literal: true

require 'vagrant-zones/action'

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used manage the zone where vagrant cannot
      class Zone < Vagrant.plugin('2', :command)
        def self.synopsis
          'Manage zones and query zone information'
        end

        def initialize(argv, env)
          @main_args, @sub_command, @sub_args = split_main_and_subcommand(argv)

          @subcommands = Vagrant::Registry.new

          @subcommands.register(:zfssnapshot) do
            require File.expand_path('zfssnapshot', __dir__)
            ZFSSnapshot
          end
          @subcommands.register(:control) do
            require File.expand_path('guest_power_controls', __dir__)
            GuestPowerControls
          end
          @subcommands.register(:console) do
            require File.expand_path('console', __dir__)
            Console
          end
          super(argv, env)
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
            subopts.banner = 'Usage: vagrant zone <subcommand> [<args>]'
            subopts.separator ''
            subopts.separator 'Available subcommands:'

            # Add the available subcommands as separators in order to print them
            # out as well.
            keys = []
            @subcommands.each { |(key, _value)| keys << key.to_s }

            keys.sort.each do |key|
              subopts.separator "     #{key}"
            end

            subopts.separator ''
            subopts.separator 'For help on any individual subcommand run `vagrant zone <subcommand> -h`'
          end

          @env.ui.info(opts.help, :prefix => false)
        end
      end
    end
  end
end
