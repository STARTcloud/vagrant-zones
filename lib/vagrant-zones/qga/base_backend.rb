# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # Shared scaffolding for QGA network backends. Subclasses configure guest
      # networking using a specific backend (netplan, NetworkManager, etc.) and
      # implement #detect? and #apply via duck typing. #verify and #cleanup have
      # working defaults that subclasses may override.
      class BaseBackend
        # Human-readable name used in logs and error chains.
        def name
          self.class.name.split('::').last
        end

        # Re-fetch guest interfaces and confirm expected IPs are present on expected MACs.
        # Returns true when every NIC's expected IP appears on the matched MAC.
        def verify(qga, nics)
          ifs = qga.network_interfaces
          nics.all? do |entry|
            mac = entry[:mac]
            expected_ip = entry[:ip]
            next true if expected_ip.nil? || expected_ip.empty?

            iface = ifs.find { |i| QGA.normalize_mac(i['hardware-address'].to_s) == mac }
            next false unless iface

            addrs = iface['ip-addresses'] || []
            addrs.any? { |a| a['ip-address-type'] == 'ipv4' && a['ip-address'] == expected_ip }
          end
        rescue StandardError
          false
        end

        # Default no-op cleanup; backends that write files override this.
        def cleanup(*)
          nil
        end
      end
    end
  end
end
