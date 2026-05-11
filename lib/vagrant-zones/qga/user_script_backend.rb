# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # Escape hatch: pipes a host-side script through `bash -c` per NIC, passing
      # per-NIC network parameters as environment variables.
      # Activated only when config.qga_network_script is set; bypasses all detection.
      class UserScriptBackend < BaseBackend
        def initialize(script_path)
          super()
          @script_path = script_path
        end

        def detect?(_qga)
          File.exist?(@script_path)
        end

        def apply(uii, qga, nics, _ctx)
          contents = File.read(@script_path)
          nics.each do |entry|
            env = build_env(entry)
            uii.info(I18n.t('vagrant_zones.qga_user_script_run') + " #{entry[:vnic_name]}")
            result = qga.exec('/bin/bash', args: ['-s'], env: env, input_data: contents, timeout: 300)
            raise Errors::QGAError, message: "user script failed for #{entry[:vnic_name]} (exit #{result[:exitcode]}): #{result[:stderr]}" if result[:exitcode] != 0
          end
        end

        private

        def build_env(entry)
          dns_list = entry[:dns] ? entry[:dns].map { |s| s['nameserver'] }.compact.join(',') : ''
          [
            "VAGRANT_QGA_VNIC=#{entry[:vnic_name]}",
            "VAGRANT_QGA_MAC=#{entry[:mac]}",
            "VAGRANT_QGA_IP=#{entry[:ip]}",
            "VAGRANT_QGA_NETMASK=#{entry[:netmask]}",
            "VAGRANT_QGA_GATEWAY=#{entry[:gateway]}",
            "VAGRANT_QGA_DNS=#{dns_list}",
            "VAGRANT_QGA_DHCP4=#{entry[:dhcp4] ? 'true' : 'false'}",
            "VAGRANT_QGA_DHCP6=#{entry[:dhcp6] ? 'true' : 'false'}",
            "VAGRANT_QGA_ROUTE=#{entry[:route]}"
          ]
        end
      end
    end
  end
end
