# frozen_string_literal: true

require 'log4r'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Zlogin strategy: drives the bhyve serial console via PTY + Expect to log in,
      # then runs SSH-based commands or further zlogin shell calls to configure
      # networking inside the guest. Long-standing default behavior preserved
      # verbatim from the original driver implementation; mechanics live in
      # ZloginConsole / ZloginNetplan / ZloginDladm / ZloginWindows mixins.
      class Zlogin < Base
        include ZloginConsole
        include ZloginWindowsConsole
        include ZloginNetplan
        include ZloginDladm
        include ZloginWindows

        def wait_for_boot(uii, metrics, interrupted)
          config = @machine.provider_config
          return if config.cloud_init_enabled || interrupted

          metrics ||= {}
          metrics['instance_zlogin_boot_time'] = Util::Timer.time do
            if config.os_type.to_s.match(/windows/)
              zlogin_win_boot(uii)
            else
              zloginboot(uii)
            end
          end
          uii.info("#{I18n.t('vagrant_zones.boot_ready')} in #{metrics['instance_zlogin_boot_time']} Seconds")
        end

        def get_ip_address(uii)
          @machine.config.vm.networks.each do |(_adaptertype, opts)|
            if opts[:dhcp4] && opts[:managed]
              ip = scrape_ip_via_pty(uii, opts)
              return ip[0] if ip && !ip[0].to_s.empty?
            elsif (opts[:dhcp4] == false || opts[:dhcp4].nil?) && opts[:managed]
              static = opts[:ip].to_s
              return nil if static.empty?

              return static.gsub("\t", '')
            end
          end
          nil
        end

        def setup_network(uii)
          config = @machine.provider_config
          return if config.cloud_init_enabled

          @machine.config.vm.networks.each do |(adaptertype, opts)|
            case adaptertype.to_s
            when 'public_network'  then setup_public_nic(uii, opts, config)
            when 'private_network' then setup_private_nic(uii, opts, config)
            end
          end
        end

        def control(uii, action)
          config = @machine.provider_config
          case action
          when /restart/
            @driver.ssh_run_command(uii, config.safe_restart || 'sudo shutdown -r')
          when 'shutdown'
            @driver.ssh_run_command(uii, config.safe_shutdown || 'sudo init 0 || true')
          else
            uii.info(I18n.t('vagrant_zones.control_no_cmd'))
          end
        end

        private

        def setup_public_nic(uii, opts, config)
          vnic_name = @driver.vname(uii, opts)
          mac = @driver.vnic_mac_for(uii, opts)
          uii.info(I18n.t('vagrant_zones.os_detect'))
          os_detected = @driver.zlogin(uii, 'uname -a')
          uii.info('Zone OS detected as: OmniOS') if os_detected.to_s.match(/SunOS/)

          if config.os_type.to_s.match(/windows/)
            zlogin_windows_setup(uii, opts, mac)
          elsif os_detected.to_s.match(/SunOS/)
            zlogin_dladm_setup(uii, opts, mac, vnic_name)
          else
            zlogin_netplan_setup(uii, opts, mac, vnic_name)
          end
        end

        def setup_private_nic(uii, opts, config)
          return if config.setup_method == 'dhcp'

          vnic_name = @driver.vname(uii, opts)
          mac = @driver.vnic_mac_for(uii, opts)
          uii.info(I18n.t('vagrant_zones.os_detect'))
          os_detected = @driver.ssh_run_command(uii, 'uname -a')
          uii.info("Zone OS detected as: #{os_detected}")
          uii.info(I18n.t('vagrant_zones.ansible_detect'))
          ansible_detected = @driver.ssh_run_command(uii, 'which ansible > /dev/null 2>&1 ; echo $?')
          uii.info('Ansible detected') if ansible_detected == '0'

          if os_detected.to_s.match(/SunOS/)
            ssh_dladm_setup(uii, opts, mac, vnic_name)
          else
            ssh_netplan_setup(uii, opts, mac, vnic_name)
          end
        end
      end
    end
  end
end
