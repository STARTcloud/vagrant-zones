# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Mixin: configure an illumos/SunOS guest's networking via dladm + ipadm + route,
      # over either the zlogin console (no SSH yet) or SSH once login is established.
      # Including class must expose @driver.
      module ZloginDladm
        def zlogin_dladm_setup(uii, opts, mac, vnic_name)
          ctx = build_dladm_context(uii, opts, mac, vnic_name)
          device, interface = discover_device(uii, mac, ctx[:sanitized_mac], via: :zlogin)
          apply_dladm_commands(uii, ctx, device, interface, via: :zlogin)
        end

        def ssh_dladm_setup(uii, opts, mac, vnic_name)
          ctx = build_dladm_context(uii, opts, mac, vnic_name)
          device, interface = discover_device(uii, mac, ctx[:sanitized_mac], via: :ssh)
          apply_dladm_commands(uii, ctx, device, interface, via: :ssh)
        end

        private

        def build_dladm_context(uii, opts, mac, vnic_name)
          uii.info(I18n.t('vagrant_zones.configure_interface_using_vnic_dladm'))
          uii.info("  #{vnic_name}")
          {
            ip: @driver.ipaddress(uii, opts),
            defrouter: opts[:gateway].to_s,
            vnic_name: vnic_name,
            shrtsubnet: IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s,
            servers: render_dladm_servers(uii, opts),
            sanitized_mac: mac.split(':').map { |segment| segment.to_i(16).to_s(16) }.join(':'),
            mac: mac,
            gateway: opts[:gateway],
            dns: opts[:dns]
          }
        end

        def render_dladm_servers(uii, opts)
          return nil if opts[:dns].nil?

          @driver.dnsservers(uii, opts).map { |server| "nameserver #{server['nameserver']}" }.join("\n")
        end

        def discover_device(uii, mac, sanitized_mac, via:)
          cmd = 'pfexec dladm show-phys -m -o LINK,ADDRESS,CLIENT | tail -n +2'
          cmd += " | grep #{sanitized_mac}" if via == :zlogin
          results = invoke_guest(uii, cmd, via).to_s.split("\n")
          device = ''
          interface = ''
          results.each do |entry|
            split_line = entry.strip.split("\r")
            next if split_line[1].nil?

            entries = split_line[1].split
            row_mac = entries[1].split(':').map { |x| format('%02x', x.to_i(16)) }.join(':')
            device = entries[0] if row_mac.match(/#{mac}/)
            interface = entries[2] if row_mac.match(/#{mac}/)
          end
          [device, interface]
        end

        def apply_dladm_commands(uii, ctx, device, interface, via:)
          delete_if = interface.to_s.match(/--/) ? '' : "pfexec ipadm delete-if #{device} && "
          rename_link = "pfexec dladm rename-link #{device} #{ctx[:vnic_name]} && "
          if_create = "pfexec ipadm create-if #{ctx[:vnic_name]}"
          static_addr = "pfexec ipadm create-addr -T static -a #{ctx[:ip]}/#{ctx[:shrtsubnet]} #{ctx[:vnic_name]}/v4vagrant"
          uii.info(I18n.t('vagrant_zones.dladm_applied')) if invoke_guest(uii, "#{delete_if} #{rename_link} #{if_create} && #{static_addr}", via)
          apply_dladm_route(uii, ctx, via)
          apply_dladm_dns(uii, ctx, via)
        end

        def apply_dladm_route(uii, ctx, via)
          route_add = if ctx[:gateway].nil?
                        via == :zlogin ? 'echo True' : ''
                      else
                        "pfexec route -p add default #{ctx[:defrouter]}"
                      end
          uii.info(I18n.t('vagrant_zones.dladm_route_applied')) if invoke_guest(uii, route_add, via)
        end

        def apply_dladm_dns(uii, ctx, via)
          return if ctx[:dns].nil?

          dns_set = "pfexec echo '#{ctx[:servers]}' | pfexec tee /etc/resolv.conf"
          uii.info(I18n.t('vagrant_zones.dladm_dns_applied')) if invoke_guest(uii, dns_set, via)
        end

        def invoke_guest(uii, cmd, via)
          via == :zlogin ? @driver.zlogin(uii, cmd) : @driver.ssh_run_command(uii, cmd)
        end
      end
    end
  end
end
