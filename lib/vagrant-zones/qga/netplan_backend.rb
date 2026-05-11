# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Writes /etc/netplan/<vnic>.yaml per NIC and runs `netplan apply`.
      class NetplanBackend < BaseBackend
        NETPLAN_BIN = '/usr/sbin/netplan'

        def detect?(qga)
          qga.exec('/usr/bin/test', args: ['-x', NETPLAN_BIN], timeout: 10)[:exitcode].zero?
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          nics.each do |entry|
            yaml = render_yaml(entry)
            path = "/etc/netplan/#{entry[:vnic_name]}.yaml"
            write_result = qga.exec('/bin/sh',
                                    args: ['-c', "cat > #{path} && chmod 600 #{path}"],
                                    input_data: yaml,
                                    timeout: 30)
            raise Errors::QGAError, message: "netplan write failed for #{path}: #{write_result[:stderr]}" if write_result[:exitcode] != 0

            uii.info("#{I18n.t('vagrant_zones.qga_backend_apply')} netplan #{path}")
          end
          result = qga.exec(NETPLAN_BIN, args: ['apply'], timeout: 60)
          raise Errors::QGAError, message: "netplan apply failed: #{result[:stderr]}" if result[:exitcode] != 0
        end

        def cleanup(uii, qga, nics)
          nics.each do |entry|
            qga.exec('/bin/rm', args: ['-f', "/etc/netplan/#{entry[:vnic_name]}.yaml"], timeout: 10)
          end
          uii.info("#{I18n.t('vagrant_zones.qga_backend_cleanup')} netplan")
        end

        private

        def render_yaml(entry)
          prefix = IPAddr.new(entry[:netmask].to_s).to_i.to_s(2).count('1') if entry[:netmask]
          lines = []
          lines << 'network:'
          lines << '  version: 2'
          lines << '  ethernets:'
          lines << "    #{entry[:vnic_name]}:"
          lines << '      match:'
          lines << "        macaddress: #{entry[:mac]}"
          lines << "      set-name: #{entry[:vnic_name]}"
          if entry[:dhcp4]
            lines << '      dhcp-identifier: mac'
            lines << '      dhcp4: true'
          elsif entry[:ip]
            lines << "      addresses: [#{entry[:ip]}/#{prefix}]"
          end
          lines << "      dhcp6: #{entry[:dhcp6] ? true : false}"
          if entry[:gateway]
            route_to = entry[:route] || 'default'
            lines << '      routes:'
            lines << "        - to: #{route_to}"
            lines << "          via: #{entry[:gateway]}"
          end
          if entry[:dns] && !entry[:dns].empty?
            addrs = entry[:dns].map { |s| s['nameserver'] }.compact.join(', ')
            lines << '      nameservers:'
            lines << "        addresses: [#{addrs}]"
          end
          "#{lines.join("\n")}\n"
        end
      end
    end
  end
end
