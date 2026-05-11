# frozen_string_literal: true

require 'ipaddr'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Vanilla FreeBSD: write ifconfig_*, defaultrouter, hostname entries to
      # /etc/rc.conf.local and restart netif + routing services.
      class FreebsdBackend < BaseBackend
        RC_CONF_LOCAL = '/etc/rc.conf.local'
        BEGIN_MARKER = '# BEGIN vagrant-zones managed block'
        END_MARKER = '# END vagrant-zones managed block'

        def detect?(qga)
          os = qga.osinfo
          return false unless os['id'].to_s.downcase == 'freebsd'

          # Pure FreeBSD only here; pfSense/OPNsense handled by their own backends.
          pfsense = qga.exec('/bin/sh', args: ['-c', 'grep -q pfSense /etc/version 2>/dev/null'], timeout: 10)[:exitcode].zero?
          opnsense = qga.exec('/usr/bin/test', args: ['-d', '/usr/local/opnsense/version'], timeout: 10)[:exitcode].zero?
          !(pfsense || opnsense)
        rescue StandardError
          false
        end

        def apply(uii, qga, nics, _ctx)
          block = render_block(nics, qga)
          remove_existing_block(qga)
          append = qga.exec('/bin/sh', args: ['-c', "cat >> #{RC_CONF_LOCAL}"],
                                       input_data: block, timeout: 30)
          raise Errors::QGAError, message: "rc.conf.local append failed: #{append[:stderr]}" if append[:exitcode] != 0

          uii.info("#{I18n.t('vagrant_zones.qga_backend_apply')} freebsd-rcconf")
          netif = qga.exec('/usr/sbin/service', args: %w[netif restart], timeout: 60)
          raise Errors::QGAError, message: "service netif restart failed: #{netif[:stderr]}" if netif[:exitcode] != 0

          qga.exec('/usr/sbin/service', args: %w[routing restart], timeout: 30)
        end

        def cleanup(uii, qga, _nics)
          remove_existing_block(qga)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_cleanup')} freebsd-rcconf")
        end

        private

        def remove_existing_block(qga)
          script = "sed -i '' '/#{Regexp.escape(BEGIN_MARKER)}/,/#{Regexp.escape(END_MARKER)}/d' #{RC_CONF_LOCAL} 2>/dev/null || true"
          qga.exec('/bin/sh', args: ['-c', script], timeout: 30)
        end

        def render_block(nics, qga)
          ifs = qga.network_interfaces
          lines = []
          lines << ''
          lines << BEGIN_MARKER
          gateway = nil
          dns_servers = []
          nics.each do |entry|
            iface = ifs.find { |i| QGA.normalize_mac(i['hardware-address'].to_s) == entry[:mac] }
            ifname = iface ? iface['name'] : nil
            next if ifname.nil? || ifname.empty?

            if entry[:dhcp4]
              lines << "ifconfig_#{ifname}=\"DHCP\""
            elsif entry[:ip] && entry[:netmask]
              lines << "ifconfig_#{ifname}=\"inet #{entry[:ip]} netmask #{entry[:netmask]}\""
            end
            gateway ||= entry[:gateway].to_s if entry[:gateway]
            if entry[:dns] && !entry[:dns].empty?
              entry[:dns].each { |s| dns_servers << s['nameserver'] if s['nameserver'] }
            end
          end
          lines << "defaultrouter=\"#{gateway}\"" if gateway
          lines << END_MARKER
          lines << ''
          write_resolv(qga, dns_servers.uniq) unless dns_servers.empty?
          "#{lines.join("\n")}\n"
        end

        def write_resolv(qga, servers)
          content = "#{servers.map { |s| "nameserver #{s}" }.join("\n")}\n"
          qga.exec('/bin/sh', args: ['-c', 'cat > /etc/resolv.conf'], input_data: content, timeout: 15)
        end
      end
    end
  end
end
