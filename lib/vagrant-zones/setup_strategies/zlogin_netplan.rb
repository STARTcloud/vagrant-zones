# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Mixin: render and apply a netplan yaml file for a NIC, either via the
      # zlogin console (no SSH yet) or via SSH once login is established.
      # Including class must expose @driver.
      module ZloginNetplan
        def zlogin_netplan_setup(uii, opts, mac, vnic_name)
          @driver.zlogin(uii, 'rm -rf /etc/netplan/*.yaml') if opts[:nic_number].zero?
          yaml = render_netplan_yaml(uii, opts, mac, vnic_name)
          cmd = "echo '#{yaml}' > /etc/netplan/#{vnic_name}.yaml && chmod 400 /etc/netplan/#{vnic_name}.yaml"
          info = I18n.t('vagrant_zones.netplan_applied_static') + "/etc/netplan/#{vnic_name}.yaml"
          uii.info(info) if @driver.zlogin(uii, cmd)
          uii.info(I18n.t('vagrant_zones.netplan_applied')) if @driver.zlogin(uii, 'netplan apply')
        end

        def ssh_netplan_setup(uii, opts, mac, vnic_name)
          @driver.ssh_run_command(uii, 'sudo rm -rf /etc/netplan/*.yaml')
          yaml = render_netplan_yaml(uii, opts, mac, vnic_name, dhcp_section: true)
          cmd = "echo -e '#{yaml}' | sudo tee /etc/netplan/#{vnic_name}.yaml && chmod 400 /etc/netplan/#{vnic_name}.yaml"
          info = I18n.t('vagrant_zones.netplan_applied_static') + "/etc/netplan/#{vnic_name}.yaml"
          uii.info(info) if @driver.ssh_run_command(uii, cmd)
          uii.info(I18n.t('vagrant_zones.netplan_applied')) if @driver.ssh_run_command(uii, 'sudo netplan apply')
        end

        private

        def render_netplan_yaml(uii, opts, mac, vnic_name, dhcp_section: false)
          uii.info(I18n.t('vagrant_zones.configure_interface_using_vnic'))
          uii.info("  #{vnic_name}")
          ip = @driver.ipaddress(uii, opts)
          servers = render_netplan_servers(uii, opts)
          shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
          defrouter = opts[:gateway].to_s
          base = netplan_header(vnic_name, mac)
          base + netplan_dhcp_block(opts, dhcp_section) +
            netplan_address_block(opts, vnic_name, ip, shrtsubnet) +
            netplan_route_block(opts, defrouter) +
            netplan_nameservers_block(servers)
        end

        def render_netplan_servers(uii, opts)
          return nil if opts[:dns].nil?

          @driver.dnsservers(uii, opts).map { |server| server['nameserver'] }.join(', ')
        end

        def netplan_header(vnic_name, mac)
          %(network:\n  version: 2\n  ethernets:\n    #{vnic_name}:\n      match:\n        macaddress: #{mac}\n)
        end

        def netplan_dhcp_block(opts, dhcp_section)
          return '' unless opts[:dhcp4] || dhcp_section

          %(      dhcp-identifier: mac\n      dhcp4: #{opts[:dhcp4]}\n      dhcp6: #{opts[:dhcp6]}\n)
        end

        def netplan_address_block(opts, vnic_name, ip, shrtsubnet)
          if opts[:dhcp4]
            %(      set-name: #{vnic_name}\n)
          else
            %(      set-name: #{vnic_name}\n      addresses: [#{ip}/#{shrtsubnet}]\n)
          end
        end

        def netplan_route_block(opts, defrouter)
          return '' if opts[:gateway].nil?

          %(      routes:\n        - to: #{opts[:route]}\n          via: #{defrouter}\n)
        end

        def netplan_nameservers_block(servers)
          return '' if servers.nil?

          %(      nameservers:\n        addresses: [#{servers}])
        end
      end
    end
  end
end
