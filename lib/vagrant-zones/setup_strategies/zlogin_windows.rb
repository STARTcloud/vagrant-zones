# frozen_string_literal: true

require 'strings/ansi'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Mixin: configure a Windows guest's networking via netsh, invoked through
      # the zlogin console once SAC has been driven into a CMD session.
      # Including class must expose @driver and @machine.
      module ZloginWindows
        VZWI_MARKER = 'VZWI'

        def zlogin_windows_setup(uii, opts, _mac)
          config = @machine.provider_config
          uii.info(I18n.t('vagrant_zones.configure_win_interface_using_vnic'))
          uii.info("#{I18n.t('vagrant_zones.windows_profile_wait')} #{config.windows_profile_wait} seconds")
          sleep(config.windows_profile_wait)

          mac = @driver.vnic_mac_for(uii, opts)
          adapter_name = find_windows_adapter(uii, mac)
          if adapter_name.nil? || adapter_name.empty?
            uii.info('Could not extract adapter name from output')
            return
          end
          configure_windows_adapter(uii, opts, adapter_name)
        end

        private

        def find_windows_adapter(uii, mac)
          normalized = mac.split(':').map { |segment| segment.rjust(2, '0') }.join('-').upcase
          # rubocop:disable Style/RedundantStringEscape
          getmac_cmd = %(bash -c "getmac /v /FO csv /NH | grep \\\"#{normalized}\\\" | awk -F, '{print $1}' | sed 's/\\\"/#{VZWI_MARKER}/g'")
          # rubocop:enable Style/RedundantStringEscape
          raw_output = @driver.zlogin(uii, getmac_cmd)
          extract_windows_adapter_name(raw_output)
        end

        def extract_windows_adapter_name(raw_output)
          raw_output_str = raw_output.is_a?(Array) ? raw_output.join : raw_output.to_s
          sanitized_output = Strings::ANSI.sanitize(raw_output_str)
          sanitized_output.split(/[\r\n]+/).each do |line|
            next unless line.include?(VZWI_MARKER)

            extracted = extract_between_marker_pairs(line)
            return extracted unless extracted.nil?
          end
          nil
        end

        def extract_between_marker_pairs(line)
          positions = []
          pos = -1
          while (pos = line.index(VZWI_MARKER, pos + 1))
            positions << pos
          end
          return nil if positions.length < 2

          start_pos = positions[-2]
          end_pos = positions[-1]
          line[(start_pos + VZWI_MARKER.length)...end_pos]
        end

        def configure_windows_adapter(uii, opts, adapter_name)
          vnic_name = @driver.vname(uii, opts)
          ip = @driver.ipaddress(uii, opts)
          defrouter = opts[:gateway].to_s

          rename = %(netsh interface set interface name="#{adapter_name}" newname="#{vnic_name}")
          uii.info(I18n.t('vagrant_zones.win_applied_rename_adapter')) if @driver.zlogin(uii, rename)

          metric_param = opts[:metric] ? "metric=#{opts[:metric]}" : ''
          set_addr = %(netsh interface ipv4 set address name="#{vnic_name}" static #{ip} #{opts[:netmask]} #{defrouter} #{metric_param})
          uii.info(I18n.t('vagrant_zones.win_applied_static')) if @driver.zlogin(uii, set_addr)

          configure_windows_dns(uii, opts, vnic_name)
        end

        def configure_windows_dns(uii, opts, vnic_name)
          return if opts[:dns].nil?

          servers = @driver.dnsservers(uii, opts).map { |hash| hash['nameserver'] }
          primary = %(netsh int ipv4 set dns name="#{vnic_name}" static #{servers[0]} primary validate=no)
          uii.info(I18n.t('vagrant_zones.win_applied_dns1')) if @driver.zlogin(uii, primary)
          servers[1..].each_with_index do |dns, index|
            additional = %(netsh int ipv4 add dns name="#{vnic_name}" #{dns} index="#{index + 2}" validate=no)
            uii.info(I18n.t('vagrant_zones.win_applied_dns2')) if @driver.zlogin(uii, additional)
          end
        end
      end
    end
  end
end
