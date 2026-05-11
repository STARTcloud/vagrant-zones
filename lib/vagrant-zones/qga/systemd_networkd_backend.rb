# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Writes /etc/systemd/network/10-<vnic>.link (for MAC->name rename) and
      # 10-<vnic>.network per NIC, then restarts systemd-networkd.
      class SystemdNetworkdBackend < BaseBackend
        NETWORKD_DIR = '/etc/systemd/network'

        def detect?(qga)
          return false unless qga.exec('/usr/bin/test', args: ['-d', NETWORKD_DIR], timeout: 10)[:exitcode].zero?

          result = qga.exec('/usr/bin/systemctl', args: %w[is-active systemd-networkd], timeout: 10)
          result[:stdout].to_s.strip == 'active'
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          nics.each do |entry|
            write_link_file(qga, entry)
            write_network_file(qga, entry)
            uii.info("#{I18n.t('vagrant_zones.qga_backend_apply')} systemd-networkd #{entry[:vnic_name]}")
          end
          reload = qga.exec('/usr/bin/systemctl', args: %w[restart systemd-networkd], timeout: 30)
          raise Errors::QGAError, message: "systemd-networkd restart failed: #{reload[:stderr]}" if reload[:exitcode] != 0
        end

        def cleanup(uii, qga, nics)
          nics.each do |entry|
            qga.exec('/bin/rm', args: ['-f',
                                       "#{NETWORKD_DIR}/10-#{entry[:vnic_name]}.link",
                                       "#{NETWORKD_DIR}/10-#{entry[:vnic_name]}.network"], timeout: 10)
          end
          qga.exec('/usr/bin/systemctl', args: %w[restart systemd-networkd], timeout: 30)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_cleanup')} systemd-networkd")
        end

        private

        def write_link_file(qga, entry)
          path = "#{NETWORKD_DIR}/10-#{entry[:vnic_name]}.link"
          content = <<~LINK
            [Match]
            MACAddress=#{entry[:mac]}

            [Link]
            Name=#{entry[:vnic_name]}
          LINK
          result = qga.exec('/bin/sh', args: ['-c', "cat > #{path} && chmod 644 #{path}"],
                                       input_data: content, timeout: 30)
          raise Errors::QGAError, message: "networkd link write failed: #{result[:stderr]}" if result[:exitcode] != 0
        end

        def write_network_file(qga, entry)
          path = "#{NETWORKD_DIR}/10-#{entry[:vnic_name]}.network"
          prefix = IPAddr.new(entry[:netmask].to_s).to_i.to_s(2).count('1') if entry[:netmask]
          lines = []
          lines << '[Match]'
          lines << "Name=#{entry[:vnic_name]}"
          lines << ''
          lines << '[Network]'
          if entry[:dhcp4]
            lines << 'DHCP=ipv4'
          elsif entry[:ip]
            lines << "Address=#{entry[:ip]}/#{prefix}"
            lines << "Gateway=#{entry[:gateway]}" if entry[:gateway]
          end
          if entry[:dns] && !entry[:dns].empty?
            entry[:dns].each do |s|
              lines << "DNS=#{s['nameserver']}" if s['nameserver']
            end
          end
          content = "#{lines.join("\n")}\n"
          result = qga.exec('/bin/sh', args: ['-c', "cat > #{path} && chmod 644 #{path}"],
                                       input_data: content, timeout: 30)
          raise Errors::QGAError, message: "networkd network write failed: #{result[:stderr]}" if result[:exitcode] != 0
        end
      end
    end
  end
end
