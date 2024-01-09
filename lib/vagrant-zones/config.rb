# frozen_string_literal: true

require 'vagrant'
## Do not Modify this File! Modify the Hosts.yml, Hosts.rb, or Vagrantfile!
module VagrantPlugins
  module ProviderZone
    # This is used define the variables for the project
    class Config < Vagrant.plugin('2', :config)
      # rubocop:disable Layout/LineLength
      attr_accessor :brand, :autoboot, :setup_method, :safe_restart, :allowed_address, :post_provision_boot, :safe_shutdown, :boxshortname, :kernel, :debug, :debug_boot, :private_network, :winalcheck, :winlcheck, :lcheck, :alcheck, :snapshot_script, :diskif, :netif, :cdroms, :disk1path, :disk1size, :cpus, :cpu_configuration, :boot, :complex_cpu_conf, :memory, :vagrant_user, :vagrant_user_private_key_path, :setup_wait, :on_demand_vnics, :clean_shutdown_time, :dhcp4, :vagrant_user_pass, :firmware_type, :vm_type, :partition_id, :shared_disk_enabled, :shared_dir, :acpi, :os_type, :console, :consolehost, :consoleport, :console_onboot, :hostbridge, :sshport, :rdpport, :override, :additional_disks, :cloud_init_resolvers, :cloud_init_enabled, :cloud_init_dnsdomain, :cloud_init_password, :cloud_init_sshkey, :cloud_init_conf, :dns, :box, :vagrant_cloud_creator, :winbooted_string, :booted_string, :zunlockbootkey, :zunlockboot, :xhci_enabled, :login_wait

      # rubocop:enable Layout/LineLength

      def initialize
        super
        @brand = 'bhyve'
        @additional_disks = UNSET_VALUE
        @autoboot = true
        @post_provision_boot = false
        @kernel = nil
        @boxshortname = UNSET_VALUE
        @cdroms = nil
        @shared_dir = nil
        @os_type = 'generic'
        @lcheck = UNSET_VALUE
        @booted_string = UNSET_VALUE
        @winbooted_string = UNSET_VALUE
        @allowed_address = true
        @alcheck = 'login: '
        @winalcheck = 'EVENT: The CMD command is now available.'
        @winlcheck = 'EVENT: The CMD command is now available.'
        @zunlockbootkey = ''
        @zunlockboot = 'Importing ZFS root pool'
        @safe_restart = nil
        @safe_shutdown = nil
        @debug_boot = nil
        @debug = nil
        @shared_disk_enabled = true
        @consoleport = nil
        @consolehost = '0.0.0.0'
        @console_onboot = 'false'
        @console = 'webvnc'
        @memory = '2G'
        @diskif = 'virtio-blk'
        @netif = 'virtio-net-viona'
        @cpus = 1
        @cpu_configuration = 'simple'
        @complex_cpu_conf = UNSET_VALUE
        @boot = UNSET_VALUE
        @hostbridge = 'i440fx'
        @acpi = 'on'
        @setup_wait = 90
        @on_demand_vnics = 'true'
        @box = UNSET_VALUE
        @clean_shutdown_time = 300
        @vmtype = 'production'
        @partition_id = '0000'
        @sshport = '22'
        @rdpport = '3389'
        @vagrant_user = 'vagrant'
        @vagrant_user_pass = 'vagrant'
        @vagrant_user_private_key_path = './id_rsa'
        @xhci_enabled = 'off'
        @override = false
        @login_wait = 5
        @cloud_init_enabled = false
        @cloud_init_conf = 'on'
        @cloud_init_dnsdomain = nil
        @cloud_init_password = nil
        @cloud_init_resolvers = nil
        @cloud_init_sshkey = nil
        @private_network = nil
        @firmware_type = 'compatability'
        @vm_type = 'production'
        @setup_method = nil
        @snapshot_script = '/opt/vagrant/bin/Snapshooter.sh'
      end
    end
  end
end
