# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module QGA
      # OmniOS / illumos / SunOS: rename link, create-if, static address, route.
      class IllumosBackend < BaseBackend
        DLADM = '/usr/sbin/dladm'
        IPADM = '/usr/sbin/ipadm'
        ROUTE = '/usr/sbin/route'

        def detect?(qga)
          os = qga.osinfo
          %w[omnios sunos illumos].any? { |id| os['id'].to_s.downcase.include?(id) } ||
            os['kernel-version'].to_s =~ /illumos|SunOS/i
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          nics.each do |entry|
            device, current_if = find_device(qga, entry[:mac])
            raise Errors::QGAError, message: "illumos device for MAC #{entry[:mac]} not found" if device.nil? || device.empty?

            qga.exec(IPADM, args: ['delete-if', device], timeout: 15) if current_if && current_if != '--' && current_if != entry[:vnic_name]
            qga.exec(DLADM, args: ['rename-link', device, entry[:vnic_name]], timeout: 15) unless device == entry[:vnic_name]
            qga.exec(IPADM, args: ['create-if', entry[:vnic_name]], timeout: 15)
            apply_address(qga, entry)
            apply_route(qga, entry)
            apply_resolv(qga, entry)
            uii.info(I18n.t('vagrant_zones.qga_backend_apply') + " illumos-dladm #{entry[:vnic_name]}")
          end
        end

        private

        def find_device(qga, mac)
          result = qga.exec(DLADM, args: %w[show-phys -m -o LINK,ADDRESS,CLIENT], timeout: 15)
          return [nil, nil] if result[:exitcode] != 0

          target = QGA.normalize_mac(mac)
          lines = result[:stdout].to_s.split("\n")
          lines.shift # header
          lines.each do |line|
            cols = line.split
            next if cols.length < 2

            row_mac = QGA.normalize_mac(cols[1])
            return [cols[0], cols[2]] if row_mac == target
          end
          [nil, nil]
        end

        def apply_address(qga, entry)
          if entry[:dhcp4]
            qga.exec(IPADM, args: ['create-addr', '-T', 'dhcp', "#{entry[:vnic_name]}/v4"], timeout: 30)
            return
          end
          return unless entry[:ip] && entry[:netmask]

          prefix = IPAddr.new(entry[:netmask].to_s).to_i.to_s(2).count('1')
          qga.exec(IPADM, args: ['create-addr', '-T', 'static', '-a', "#{entry[:ip]}/#{prefix}",
                                 "#{entry[:vnic_name]}/v4vagrant"], timeout: 30)
        end

        def apply_route(qga, entry)
          return unless entry[:gateway]

          qga.exec(ROUTE, args: ['-p', 'add', 'default', entry[:gateway].to_s], timeout: 15)
        end

        def apply_resolv(qga, entry)
          return if entry[:dns].nil? || entry[:dns].empty?

          content = "#{entry[:dns].map { |s| "nameserver #{s['nameserver']}" }.join("\n")}\n"
          qga.exec('/bin/sh', args: ['-c', 'cat > /etc/resolv.conf'], input_data: content, timeout: 15)
        end
      end
    end
  end
end
