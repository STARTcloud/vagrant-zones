# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # Renames the matched adapter and assigns IP/DNS via netsh per NIC.
      class WindowsBackend < BaseBackend
        NETSH = 'netsh.exe'

        def detect?(qga)
          os = qga.osinfo
          os['id'].to_s.downcase == 'mswindows' || os['kernel-version'].to_s.include?('Windows')
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          nics.each do |entry|
            adapter = find_adapter_name(qga, entry[:mac])
            raise Errors::QGAError, message: "Windows adapter for MAC #{entry[:mac]} not found" if adapter.nil? || adapter.empty?

            rename(qga, adapter, entry[:vnic_name]) unless adapter == entry[:vnic_name]
            configure_ipv4(qga, entry)
            configure_dns(qga, entry) if entry[:dns] && !entry[:dns].empty?
            uii.info(I18n.t('vagrant_zones.qga_backend_apply') + " windows-netsh #{entry[:vnic_name]}")
          end
        end

        private

        def find_adapter_name(qga, mac)
          normalized = mac.split(':').map { |s| s.rjust(2, '0') }.join('-').upcase
          result = qga.exec('cmd.exe', args: ['/c', "getmac /v /FO csv /NH | findstr #{normalized}"], timeout: 30)
          return nil if result[:exitcode] != 0

          first_line = result[:stdout].to_s.strip.split("\n").first.to_s
          fields = first_line.split(',')
          fields[0].to_s.gsub('"', '').strip
        end

        def rename(qga, from, to)
          qga.exec(NETSH, args: ['interface', 'set', 'interface', "name=#{from}", "newname=#{to}"], timeout: 30)
        end

        def configure_ipv4(qga, entry)
          if entry[:dhcp4]
            qga.exec(NETSH, args: ['interface', 'ipv4', 'set', 'address', "name=#{entry[:vnic_name]}", 'source=dhcp'],
                            timeout: 30)
            return
          end
          args = ['interface', 'ipv4', 'set', 'address',
                  "name=#{entry[:vnic_name]}", 'static',
                  entry[:ip].to_s, entry[:netmask].to_s]
          args << entry[:gateway].to_s if entry[:gateway]
          args << "metric=#{entry[:metric]}" if entry[:metric]
          qga.exec(NETSH, args: args, timeout: 30)
        end

        def configure_dns(qga, entry)
          servers = entry[:dns].map { |s| s['nameserver'] }.compact
          return if servers.empty?

          qga.exec(NETSH, args: ['int', 'ipv4', 'set', 'dns',
                                 "name=#{entry[:vnic_name]}", 'static', servers.first,
                                 'primary', 'validate=no'], timeout: 30)
          servers.drop(1).each_with_index do |s, i|
            qga.exec(NETSH, args: ['int', 'ipv4', 'add', 'dns',
                                   "name=#{entry[:vnic_name]}", s,
                                   "index=#{i + 2}", 'validate=no'], timeout: 30)
          end
        end
      end
    end
  end
end
