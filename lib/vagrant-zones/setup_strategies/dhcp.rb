# frozen_string_literal: true

require 'log4r'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # DHCP strategy: relies on the host-side dhcpd serving the zone's
      # private etherstub. Waits for SSH to come up; the host's dhcpd provides
      # the reserved IP via Hosts.yml configuration. No in-guest configuration.
      class DHCP < Base
        def wait_for_boot(uii, metrics, interrupted)
          config = @machine.provider_config
          return if config.cloud_init_enabled

          metrics ||= {}
          metrics['instance_dhcp_ssh_time'] = Util::Timer.time do
            @driver.retryable(on: Errors::TimeoutError, tries: 60) do
              next if interrupted

              loop do
                break if interrupted
                break if @machine.communicate.ready?
              end
            end
          end
          uii.info("#{I18n.t('vagrant_zones.dhcp_boot_ready')} in #{metrics['instance_dhcp_ssh_time']} Seconds")
        end

        def get_ip_address(uii)
          config = @machine.provider_config
          uii.info(I18n.t('vagrant_zones.get_ip_address')) if config.debug
          @machine.config.vm.networks.each do |(_adaptertype, opts)|
            if opts[:dhcp4] && opts[:managed] && !opts[:ip].to_s.empty?
              return opts[:ip].to_s.gsub("\t", '')
            elsif (opts[:dhcp4] == false || opts[:dhcp4].nil?) && opts[:managed]
              static = opts[:ip].to_s
              return nil if static.empty?

              return static.gsub("\t", '')
            end
          end
          nil
        end

        def setup_network(uii)
          # The host's dhcpd provides the zone's reserved address via the etherstub;
          # the guest auto-configures over DHCP, so no in-guest setup is required.
          uii.info(I18n.t('vagrant_zones.chk_dhcp_addr')) if @machine.provider_config.debug
          nil
        end

        def control(uii, action)
          config = @machine.provider_config
          case action
          when /restart/
            command = config.safe_restart || 'sudo shutdown -r'
            @driver.ssh_run_command(uii, command)
          when 'shutdown'
            command = config.safe_shutdown || 'sudo init 0 || true'
            @driver.ssh_run_command(uii, command)
          else
            uii.info(I18n.t('vagrant_zones.control_no_cmd'))
          end
        end
      end
    end
  end
end
