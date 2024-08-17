# frozen_string_literal: true

require 'vagrant/action/builder'
require 'log4r'

module VagrantPlugins
  module ProviderZone
    # Run actions against the machine
    module Action
      include Vagrant::Action::Builtin
      @logger = Log4r::Logger.new('vagrant_zones::action')

      # This action is called to bring the box up from nothing.
      def self.action_up
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |env, b2|
            if env[:result]
              env[:halt_on_error] = true
              b2.use action_start
            elsif !env[:result]
              b2.use Import
              b2.use HandleBox
              b2.use BoxCheckOutdated
              b2.use Create
              b2.use Network
              b2.use Start
              b2.use WaitTillBoot
              b2.use Setup
              b2.use WaitTillUp
              b2.use Provision
              b2.use NetworkingCleanup
              b2.use SetHostname
              b2.use SyncedFolders
              b2.use SyncedFolderCleanup
            end
          end
        end
      end

      # Assuming VM is created, just start it. This action is not called directly by any subcommand.
      def self.action_start
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsState, :running do |env, b1|
            if env[:result]
              b1.use Message, I18n.t('vagrant_zones.states.is_running')
              next
            end
            b1.use Call, IsState, :uncleaned do |env2, b2|
              b2.use Cleanup if env2[:result]
            end
            b1.use Start
            b1.use WaitTillUp
          end
        end
      end

      def self.action_restart
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |_env, b2|
            b2.use Call, IsState, :stopped do |env2, b3|
              unless env2[:result]
                b3.use WaitTillUp
                b3.use Restart
              end
            end
          end
        end
      end

      def self.action_shutdown
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |_env, b2|
            b2.use Call, IsState, :stopped do |env2, b3|
              unless env2[:result]
                b3.use WaitTillUp
                b3.use Shutdown
              end
            end
          end
        end
      end

      # This is the action that is primarily responsible for halting the virtual machine.
      def self.action_halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use NotCreated
              next
            end
            b2.use Halt if env[:result]
          end
        end
      end

      # This action is called to SSH into the machine.
      def self.action_ssh
        Vagrant::Action::Builder.new.tap do |b|
          b.use SSHExec
        end
      end

      def self.action_ssh_run
        Vagrant::Action::Builder.new.tap do |b|
          b.use SSHRun
        end
      end

      # This action is called when you try to package an existing virtual machine to an box image.
      def self.action_package
        Vagrant::Action::Builder.new.tap do |b|
          b.use Package
        end
      end

      # This is the action that is primarily responsible for completely freeing the resources of the underlying virtual machine.
      def self.action_destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |env1, b2|
            unless env1[:result]
              b2.use MessageNotCreated
              # Try to destroy anyways
              b2.use Call, DestroyConfirm do |env2, b3|
                b3.use Destroy if env2[:result]
              end
              next
            end
            b2.use Call, DestroyConfirm do |env2, b3|
              b3.use Destroy if env2[:result]
            end
          end
        end
      end

      # This action is called when `vagrant provision` is called.
      def self.action_provision
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |_env, b2|
            b2.use Call, IsState, :running do |_env2, b3|
              b3.use Provision
            end
          end
        end
      end

      # This is the action implements the reload command It uses the halt and start actions
      def self.action_reload
        Vagrant::Action::Builder.new.tap do |b|
          b.use Call, IsCreated do |env, b2|
            unless env[:result]
              b2.use NotCreated
              next
            end
            b2.use action_halt
            b2.use action_start
          end
        end
      end

      def self.action_create_zfs_snapshots
        Vagrant::Action::Builder.new.tap do |b|
          # b.use ConfigValidate # is this per machine?
          b.use CreateSnapshots
        end
      end

      def self.action_delete_zfs_snapshots
        Vagrant::Action::Builder.new.tap do |b|
          b.use DeleteSnapshots
        end
      end

      def self.action_configure_zfs_snapshots
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigureSnapshots
        end
      end

      def self.action_box_outdated
        Builder.new.tap do |b|
          b.use Builtin::BoxCheckOutdated
        end
      end

      # This is the action that will remove a box given a name (and optionally
      # a provider). This middleware sequence is built-in to Vagrant. Plugins
      # can hook into this like any other middleware sequence.
      def self.action_box_remove
        Builder.new.tap do |b|
          b.use Builtin::BoxRemove
        end
      end

      action_root = Pathname.new(File.expand_path('action', __dir__))
      autoload :Import, action_root.join('import')
      autoload :Create, action_root.join('create')
      autoload :Network, action_root.join('network')
      autoload :Setup, action_root.join('setup')
      autoload :Start, action_root.join('start')
      autoload :MessageNotCreated, action_root.join('message_not_created')
      autoload :NetworkingCleanup, action_root.join('network_cleanup')
      autoload :IsCreated, action_root.join('is_created')
      autoload :NotCreated, action_root.join('not_created')
      autoload :CreateSnapshots, action_root.join('create_zfs_snapshots')
      autoload :DeleteSnapshots, action_root.join('delete_zfs_snapshots')
      autoload :ConfigureSnapshots, action_root.join('configure_zfs_snapshots')
      autoload :Halt, action_root.join('halt')
      autoload :Destroy, action_root.join('destroy')
      autoload :WaitTillBoot, action_root.join('wait_till_boot')
      autoload :WaitTillUp, action_root.join('wait_till_up')
      autoload :Restart, action_root.join('restart')
      autoload :Shutdown, action_root.join('shutdown')
      autoload :PrepareNFSValidIds, action_root.join('prepare_nfs_valid_ids.rb')
      autoload :Package, action_root.join('package.rb')
    end
  end
end
