# frozen_string_literal: true

require 'ipaddr'
require 'securerandom'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Writes per-NIC keyfiles under /etc/NetworkManager/system-connections/
      # and reloads via `nmcli connection reload`.
      class NetworkManagerBackend < BaseBackend
        KEYFILE_DIR = '/etc/NetworkManager/system-connections'
        NMCLI_BIN = '/usr/bin/nmcli'

        def detect?(qga)
          return false unless qga.exec('/usr/bin/test', args: ['-x', NMCLI_BIN], timeout: 10)[:exitcode].zero?

          result = qga.exec('/usr/bin/systemctl', args: %w[is-active NetworkManager], timeout: 10)
          result[:stdout].to_s.strip == 'active'
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          nics.each do |entry|
            keyfile = render_keyfile(entry)
            path = "#{KEYFILE_DIR}/#{entry[:vnic_name]}.nmconnection"
            write_result = qga.exec('/bin/sh',
                                    args: ['-c', "mkdir -p #{KEYFILE_DIR} && cat > #{path} && chmod 600 #{path}"],
                                    input_data: keyfile,
                                    timeout: 30)
            raise Errors::QGAError, message: "NM keyfile write failed for #{path}: #{write_result[:stderr]}" if write_result[:exitcode] != 0

            uii.info("#{I18n.t('vagrant_zones.qga_backend_apply')} NetworkManager #{path}")
          end
          reload = qga.exec(NMCLI_BIN, args: %w[connection reload], timeout: 30)
          raise Errors::QGAError, message: "nmcli connection reload failed: #{reload[:stderr]}" if reload[:exitcode] != 0

          nics.each do |entry|
            qga.exec(NMCLI_BIN, args: ['connection', 'up', entry[:vnic_name]], timeout: 30)
          end
        end

        def cleanup(uii, qga, nics)
          nics.each do |entry|
            qga.exec('/bin/rm', args: ['-f', "#{KEYFILE_DIR}/#{entry[:vnic_name]}.nmconnection"], timeout: 10)
          end
          qga.exec(NMCLI_BIN, args: %w[connection reload], timeout: 30)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_cleanup')} NetworkManager")
        end

        private

        def render_keyfile(entry)
          prefix = IPAddr.new(entry[:netmask].to_s).to_i.to_s(2).count('1') if entry[:netmask]
          uuid = SecureRandom.uuid
          lines = []
          lines << '[connection]'
          lines << "id=#{entry[:vnic_name]}"
          lines << "uuid=#{uuid}"
          lines << 'type=ethernet'
          lines << "interface-name=#{entry[:vnic_name]}"
          lines << ''
          lines << '[ethernet]'
          lines << "mac-address=#{entry[:mac].upcase}"
          lines << ''
          lines << '[ipv4]'
          if entry[:dhcp4]
            lines << 'method=auto'
          elsif entry[:ip]
            lines << 'method=manual'
            lines << "addresses=#{entry[:ip]}/#{prefix}"
            lines << "gateway=#{entry[:gateway]}" if entry[:gateway]
            if entry[:dns] && !entry[:dns].empty?
              addrs = entry[:dns].map { |s| s['nameserver'] }.compact.join(';')
              lines << "dns=#{addrs};"
            end
          else
            lines << 'method=disabled'
          end
          lines << ''
          lines << '[ipv6]'
          lines << "method=#{entry[:dhcp6] ? 'auto' : 'ignore'}"
          "#{lines.join("\n")}\n"
        end
      end
    end
  end
end
