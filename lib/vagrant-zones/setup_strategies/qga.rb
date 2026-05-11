# frozen_string_literal: true

require 'log4r'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # QGA strategy: waits on the QEMU Guest Agent UNIX socket, then dispatches
      # per-guest-OS network configuration through QGA::Dispatcher. Replaces the
      # zlogin PTY login dance and brittle expect-based shell scraping.
      class QGA < Base
        # TODO(ipv6): qga get_ip_address returns IPv4 only; matches existing v4-only behavior.

        def wait_for_boot(uii, metrics, interrupted)
          config = @machine.provider_config
          return if config.cloud_init_enabled || interrupted

          metrics ||= {}
          metrics['instance_qga_socket_time'] = Util::Timer.time do
            uii.info("#{I18n.t('vagrant_zones.qga_wait_socket')} #{client.socket_path}")
            client.wait_for_socket(config.setup_wait)
          end
          return if interrupted

          metrics['instance_qga_ping_time'] = Util::Timer.time do
            uii.info(I18n.t('vagrant_zones.qga_wait_ping'))
            client.wait_for_ready(config.setup_wait)
          end
          uii.info(I18n.t('vagrant_zones.qga_ready'))
        end

        def get_ip_address(uii)
          ifs = client.network_interfaces
          @machine.config.vm.networks.each do |(_adaptertype, opts)|
            mac = @driver.vnic_mac_for(uii, opts)
            next if mac.nil? || mac.empty?

            iface = ifs.find { |i| ProviderZone::QGA.normalize_mac(i['hardware-address'].to_s) == mac }
            next unless iface

            v4 = (iface['ip-addresses'] || []).find do |a|
              a['ip-address-type'] == 'ipv4' && !a['ip-address'].to_s.start_with?('127.')
            end
            return v4['ip-address'] if v4
          end
          nil
        rescue StandardError => e
          @logger.warn("qga get_ip_address: #{e.message}")
          nil
        end

        def setup_network(uii)
          config = @machine.provider_config
          return if config.cloud_init_enabled

          nics = build_nics(uii)
          dispatcher = ProviderZone::QGA::Dispatcher.new(client, config)
          dispatcher.dispatch(uii, nics)
        end

        def control(uii, action)
          case action
          when /restart/
            uii.info("#{I18n.t('vagrant_zones.qga_shutdown')} (reboot)")
            client.shutdown('reboot')
          when 'shutdown'
            uii.info("#{I18n.t('vagrant_zones.qga_shutdown')} (powerdown)")
            client.shutdown('powerdown')
          else
            uii.info(I18n.t('vagrant_zones.control_no_cmd'))
          end
        end

        private

        def client
          @client ||= ProviderZone::QGA::Client.new(socket_path)
        end

        def socket_path
          config = @machine.provider_config
          boot = config.boot
          name = @machine.name
          "/#{boot['array']}/#{boot['dataset']}/#{name}/path/root/tmp/qga.sock"
        end

        def build_nics(uii)
          @machine.config.vm.networks.map do |(_adaptertype, opts)|
            {
              vnic_name: @driver.vname(uii, opts),
              mac: @driver.vnic_mac_for(uii, opts),
              ip: opts_ip(opts),
              netmask: opts[:netmask],
              gateway: opts[:gateway],
              dhcp4: opts[:dhcp4],
              dhcp6: opts[:dhcp6],
              dns: opts[:dns],
              route: opts[:route],
              metric: opts[:metric]
            }
          end
        end

        def opts_ip(opts)
          ip = opts[:ip].to_s
          return nil if ip.empty?

          ip.gsub("\t", '')
        end
      end
    end
  end
end
