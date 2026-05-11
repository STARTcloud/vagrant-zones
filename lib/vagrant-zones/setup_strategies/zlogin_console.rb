# frozen_string_literal: true

require 'pty'
require 'expect'
require 'timeout'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Mixin: PTY/Expect interactions over `zlogin -C` for the bhyve serial console
      # of Unix-family guests (Linux, illumos). Provides login automation and
      # IP-address scraping. Windows SAC handling lives in ZloginWindowsConsole.
      # Including class must expose @driver and @machine.
      module ZloginConsole
        def zloginboot(uii)
          name = @machine.name
          config = @machine.provider_config
          markers = boot_markers(config)
          uii.info(I18n.t('vagrant_zones.automated-zlogin'))
          PTY.spawn("pfexec zlogin -C #{name}") do |zread, zwrite, pid|
            @driver.configure_pty_encoding(zread)
            Timeout.timeout(config.setup_wait) do
              wait_for_boot_banner(uii, zread, zwrite, config, markers)
              perform_login(uii, zread, zwrite, config, markers)
              Process.kill('HUP', pid)
            end
          end
        end

        def scrape_ip_via_pty(uii, opts)
          name = @machine.name
          config = @machine.provider_config
          ctx = {
            uii: uii,
            config: config,
            markers: boot_markers(config).merge(pcheck: 'Password:'),
            vnic_name: "vnic#{@driver.nictype(opts)}#{@driver.vtype(config)}_#{config.partition_id}_#{opts[:nic_number]}"
          }
          ip = nil
          PTY.spawn("pfexec zlogin -C #{name}") do |zread, zwrite, pid|
            @driver.configure_pty_encoding(zread)
            Timeout.timeout(config.setup_wait) do
              ip = scrape_ip_session(zread, zwrite, ctx)
              Process.kill('HUP', pid)
            end
          end
          ip
        end

        private

        def boot_markers(config)
          {
            lcheck: config.lcheck || ':~',
            alcheck: config.alcheck || 'login:',
            bstring: config.booted_string || ' OK ',
            zunlockboot: config.zunlockboot || 'Importing ZFS root pool',
            zunlockbootkey: config.zunlockbootkey,
            pcheck: 'Password:'
          }
        end

        def wait_for_boot_banner(uii, zread, zwrite, config, markers)
          rsp = []
          loop do
            zread.expect(/\r\n/) do |line|
              line = line.first if line.is_a?(Array)
              encoded_line = @driver.scrub_console_output(line)
              rsp.push encoded_line unless encoded_line.empty?
            end
            uii.info(rsp[-1]) if config.debug_boot && !rsp.empty?
            handle_zfs_unlock(uii, zwrite, rsp, markers)
            next unless !rsp.empty? && rsp[-1].match(/#{markers[:bstring]}/)

            sleep(15)
            zwrite.printf("\n")
            return
          end
        end

        def handle_zfs_unlock(uii, zwrite, rsp, markers)
          return unless !rsp.empty? && rsp[-1].match(/#{markers[:zunlockboot]}/)

          sleep(2)
          zwrite.printf("#{markers[:zunlockbootkey]}\n") if markers[:zunlockbootkey]
          zwrite.printf("\n")
          uii.info(I18n.t('vagrant_zones.automated-zbootunlock'))
        end

        def perform_login(uii, zread, zwrite, config, markers)
          if zread.expect(/#{markers[:alcheck]}/)
            uii.info(I18n.t('vagrant_zones.automated-zlogin-user'))
            zwrite.printf("#{@driver.user(@machine)}\n")
            sleep(config.login_wait)
          end
          if zread.expect(/#{markers[:pcheck]}/)
            uii.info(I18n.t('vagrant_zones.automated-zlogin-pass'))
            zwrite.printf("#{@driver.vagrantuserpass(@machine)}\n")
            sleep(config.login_wait)
          end
          zwrite.printf("\n")
          return unless zread.expect(/#{markers[:lcheck]}/)

          uii.info(I18n.t('vagrant_zones.automated-zlogin-root'))
          zwrite.printf("sudo su -\n")
          sleep(config.login_wait)
        end

        def scrape_ip_session(zread, zwrite, ctx)
          rsp = []
          command = "ip -4 addr show dev #{ctx[:vnic_name]} | grep -Po 'inet \\K[\\d.]+' \r\n"
          logged_in = scrape_ip_login(zread, zwrite, ctx[:markers], rsp)
          scrape_ip_login_credentials(zread, zwrite, ctx[:markers]) unless logged_in
          ctx[:uii].info('Gathering IP') if ctx[:config].debug_boot
          zwrite.printf(command)
          scrape_ip_response(zread, rsp)
        end

        def scrape_ip_login(zread, zwrite, markers, rsp)
          i = 0
          logged_in = false
          loop do
            zread.expect(/\r\n/) { |line| rsp.push(@driver.scrub_console_output(line)) }
            logged_in = true if rsp[-1].to_s.match(/(#{Regexp.quote(markers[:lcheck])})/) || rsp[-1].to_s.match(/(:~)/)
            zwrite.printf("\r\n") if i < 1
            i += 1
            break if logged_in || rsp[-1].to_s.match(/(#{Regexp.quote(markers[:alcheck])})/)
          end
          logged_in
        end

        def scrape_ip_login_credentials(zread, zwrite, markers)
          zwrite.printf("#{@driver.user(@machine)}\n") if zread.expect(/#{Regexp.quote(markers[:alcheck])}/)
          zwrite.printf("#{@driver.vagrantuserpass(@machine)}\n") if zread.expect(/#{Regexp.quote(markers[:pcheck])}/)
          zread.expect(/#{Regexp.quote(markers[:lcheck])}/)
        end

        def scrape_ip_response(zread, rsp)
          ip = nil
          loop do
            zread.expect(/\r\n/) { |line| rsp.push(@driver.scrub_console_output(line)) }
            ip = rsp[-1].to_s.match(/((?:[0-9]{1,3}\.){3}[0-9]{1,3})/)
            break if ip
          end
          ip
        end
      end
    end
  end
end
