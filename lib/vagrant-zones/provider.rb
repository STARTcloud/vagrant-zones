# frozen_string_literal: true

require 'vagrant'
require 'log4r'

module VagrantPlugins
  # This is a module to assist in managing, creating bhyve, kvm, and lx zones
  module ProviderZone
    autoload :Driver, 'vagrant-zones/driver'
    # This is a module to assist in managing, creating bhyve, kvm, and lx zones
    class Provider < Vagrant.plugin('2', :provider)
      def initialize(machine)
        @logger = Log4r::Logger.new('vagrant::provider::zone')
        @machine = machine
        super
      end

      def driver
        return @driver if @driver

        @driver = Driver.new(@machine)
      end

      def ssh_info
        # We just return nil if were not able to identify the VM's IP and
        # let Vagrant core deal with it like docker provider does
        return nil if state.id != :running
        return nil unless driver.get_ip_address('ssh_info')

        passwordauth = 'passwordauth'
        ssh_info = {
          host: driver.get_ip_address('ssh_info'),
          port: driver.sshport(@machine).to_s,
          password: driver.vagrantuserpass(@machine).to_s,
          username: driver.user(@machine),
          private_key_path: driver.userprivatekeypath(@machine).to_s,
          PasswordAuthentication: passwordauth
        }
        ssh_info unless ssh_info.nil?
      end

      # This should return an action callable for the given name.
      # @param [Symbol] name Name of the action.
      # @return [Object] A callable action sequence object, whether it
      #        is a proc, object, etc.
      def action(name)
        # Attempt to get the action method from the Action class if it
        # exists, otherwise return nil to show that we don't support the
        # given action
        action_method = "action_#{name}"
        return Action.send(action_method) if Action.respond_to?(action_method)

        nil
      end

      # This method is called if the underying machine ID changes. Providers
      # can use this method to load in new data for the actual backing
      # machine or to realize that the machine is now gone (the ID can
      # become `nil`). No parameters are given, since the underlying machine
      # is simply the machine instance given to this object. And no
      # return value is necessary.
      def machine_id_changed
        nil
      end

      def state
        state_id = nil
        state_id = :not_created unless @machine.id
        state_id = driver.state(@machine) if @machine.id && !state_id
        # This is a special pseudo-state so that we don't set the
        # NOT_CREATED_ID while we're setting up the machine. This avoids
        # clearing the data dir.
        state_id = :preparing if @machine.id == 'preparing'
        # Get the short and long description
        short = state_id.to_s.tr('_', ' ')
        # If we're not created, then specify the special ID flag
        state_id = Vagrant::MachineState::NOT_CREATED_ID if state_id == :not_created
        # Return the MachineState object
        Vagrant::MachineState.new(state_id, short, short)
      end
    end
  end
end
