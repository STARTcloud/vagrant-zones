# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to manage ZFS snapshtos for the zone
      class ZFSSnapshot < Vagrant.plugin('2', :command)
        def initialize(argv, env)
          @main_args, @sub_command, @sub_args = split_main_and_subcommand(argv)

          @subcommands = Vagrant::Registry.new
          @subcommands.register(:list) do
            require File.expand_path('list_snapshots', __dir__)
            ListSnapshots
          end
          @subcommands.register(:create) do
            require File.expand_path('create_snapshots', __dir__)
            CreateSnapshots
          end
          @subcommands.register(:delete) do
            require File.expand_path('delete_snapshots', __dir__)
            DeleteSnapshots
          end
          @subcommands.register(:configure) do
            require File.expand_path('configure_snapshots', __dir__)
            ConfigureSnapshots
          end
          super
        end

        def execute
          if @main_args.include?('-h') || @main_args.include?('--help')
            # Print the help for all the vagrant-zones commands.
            return help
          end

          command_class = @subcommands.get(:create) if @sub_command.nil?
          command_class = @subcommands.get(@sub_command.to_sym) if @sub_command

          subargs = @sub_args unless @sub_args.nil?
          @logger.debug("Invoking command class: #{command_class} #{subargs.inspect}")

          # Initialize and execute the command class
          command_class.new(subargs, @env).execute
        end

        def help
          opts = OptionParser.new do |subopts|
            subopts.banner = 'Usage: vagrant zone zfssnapshot <subcommand> [<args>]'
            subopts.separator ''
            subopts.separator 'Available subcommands:'
            # Add the available subcommands as separators in order to print them
            # out as well.
            keys = @subcommands.map { |(key, _value)| key.to_s }.sort
            keys.each do |key|
              subopts.separator "     #{key}"
            end
            subopts.separator ''
            subopts.separator 'For help on any individual subcommand run `vagrant zone zfssnapshot <subcommand> -h`'
          end
          @env.ui.info(opts.help, :prefix => false)
        end
      end
    end
  end
end
