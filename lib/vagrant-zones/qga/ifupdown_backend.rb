# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Rewrites a managed block in /etc/network/interfaces and brings interfaces up.
      # Block is delimited by BEGIN/END marker comments so subsequent applies stay idempotent.
      class IfupdownBackend < BaseBackend
        IFACES_PATH = '/etc/network/interfaces'
        BEGIN_MARKER = '# BEGIN vagrant-zones managed block'
        END_MARKER = '# END vagrant-zones managed block'

        def detect?(qga)
          qga.exec('/usr/bin/test', args: ['-f', IFACES_PATH], timeout: 10)[:exitcode].zero? &&
            qga.exec('/usr/bin/test', args: ['-x', '/sbin/ifup'], timeout: 10)[:exitcode].zero?
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          block = render_block(nics)
          remove_existing_block(qga)
          append_result = qga.exec('/bin/sh', args: ['-c', "cat >> #{IFACES_PATH}"],
                                              input_data: block, timeout: 30)
          raise Errors::QGAError, message: "ifupdown append failed: #{append_result[:stderr]}" if append_result[:exitcode] != 0

          uii.info("#{I18n.t('vagrant_zones.qga_backend_apply')} ifupdown")
          nics.each do |entry|
            qga.exec('/sbin/ifdown', args: [entry[:vnic_name]], timeout: 30)
            up = qga.exec('/sbin/ifup', args: [entry[:vnic_name]], timeout: 60)
            raise Errors::QGAError, message: "ifup #{entry[:vnic_name]} failed: #{up[:stderr]}" if up[:exitcode] != 0
          end
        end

        def cleanup(uii, qga, _nics)
          remove_existing_block(qga)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_cleanup')} ifupdown")
        end

        private

        def remove_existing_block(qga)
          script = "sed -i '/#{Regexp.escape(BEGIN_MARKER)}/,/#{Regexp.escape(END_MARKER)}/d' #{IFACES_PATH}"
          qga.exec('/bin/sh', args: ['-c', script], timeout: 30)
        end

        def render_block(nics)
          lines = []
          lines << ''
          lines << BEGIN_MARKER
          nics.each do |entry|
            lines.concat(render_iface(entry))
            lines << ''
          end
          lines << END_MARKER
          lines << ''
          lines.join("\n")
        end

        def render_iface(entry)
          prefix = IPAddr.new(entry[:netmask].to_s).to_i.to_s(2).count('1') if entry[:netmask]
          out = []
          out << "auto #{entry[:vnic_name]}"
          if entry[:dhcp4]
            out << "iface #{entry[:vnic_name]} inet dhcp"
          elsif entry[:ip]
            out << "iface #{entry[:vnic_name]} inet static"
            out << "    address #{entry[:ip]}/#{prefix}"
            out << "    gateway #{entry[:gateway]}" if entry[:gateway]
            out << "    hwaddress ether #{entry[:mac]}" if entry[:mac]
            if entry[:dns] && !entry[:dns].empty?
              addrs = entry[:dns].map { |s| s['nameserver'] }.compact.join(' ')
              out << "    dns-nameservers #{addrs}"
            end
          else
            out << "iface #{entry[:vnic_name]} inet manual"
          end
          out
        end
      end
    end
  end
end
