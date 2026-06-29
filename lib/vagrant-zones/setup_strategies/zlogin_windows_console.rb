# frozen_string_literal: true

require 'pty'
require 'expect'
require 'timeout'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Mixin: drive Windows Server's Special Administration Console (SAC) over
      # `zlogin -C` to spawn a CMD channel and authenticate, leaving the zone
      # ready for in-guest commands. Including class must expose @driver and @machine.
      module ZloginWindowsConsole
        SAC_MARKERS = {
          cmd_avail: 'EVENT: The CMD command is now available',
          channel_created: 'EVENT:   A new channel has been created',
          channel_access: 'Use any other key to view this channel',
          prompt: 'system32>'
        }.freeze

        def zlogin_win_boot(uii)
          name = @machine.name
          config = @machine.provider_config
          uii.info(I18n.t('vagrant_zones.automated-windows-zlogin'))
          PTY.spawn("pfexec zlogin -C #{name}") do |zread, zwrite, pid|
            @driver.configure_pty_encoding(zread)
            Timeout.timeout(config.setup_wait) { perform_windows_sac_login(uii, zread, zwrite, pid) }
          end
        end

        private

        def perform_windows_sac_login(uii, zread, zwrite, pid)
          uii.info(I18n.t('vagrant_zones.windows_skip_first_boot')) if zread.expect(/#{SAC_MARKERS[:cmd_avail]}/)
          sleep(3)
          windows_open_cmd_channel(uii, zread, zwrite)
          windows_credentials(uii, zread, zwrite)
          return unless zread.expect(/#{SAC_MARKERS[:prompt]}/i)

          uii.info(I18n.t('vagrant_zones.windows_cmd_accessible'))
          sleep(5)
          Process.kill('HUP', pid)
        end

        def windows_open_cmd_channel(uii, zread, zwrite)
          if zread.expect(/#{SAC_MARKERS[:cmd_avail]}/)
            uii.info(I18n.t('vagrant_zones.windows_start_cmd'))
            zwrite.printf("cmd\n")
          end
          if zread.expect(/#{SAC_MARKERS[:channel_created]}/)
            uii.info(I18n.t('vagrant_zones.windows_access_session'))
            zwrite.printf("\e\t")
          end
          return unless zread.expect(/#{SAC_MARKERS[:channel_access]}/)

          uii.info(I18n.t('vagrant_zones.windows_access_session_presskey'))
          zwrite.printf('o')
        end

        def windows_credentials(uii, zread, zwrite)
          if zread.expect(/Username:/)
            uii.info(I18n.t('vagrant_zones.windows_enter_username'))
            zwrite.printf("#{@driver.user(@machine)}\n")
          end
          if zread.expect(/Domain/)
            uii.info(I18n.t('vagrant_zones.windows_enter_domain'))
            zwrite.printf("\n")
          end
          return unless zread.expect(/Password/)

          uii.info(I18n.t('vagrant_zones.windows_enter_password'))
          zwrite.printf("#{@driver.vagrantuserpass(@machine)}\n")
        end
      end
    end
  end
end
