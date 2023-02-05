# frozen_string_literal: true

require 'log4r'
require 'fileutils'
require 'digest/md5'
require 'io/console'
require 'ruby_expect'
require 'netaddr'
require 'ipaddr'
require 'vagrant/util/numeric'
require 'pty'
require 'expect'
require 'vagrant'
require 'resolv'
require 'vagrant-zones/util/timer'
require 'vagrant-zones/util/subprocess'
require 'vagrant/util/retryable'

module VagrantPlugins
  module ProviderZone
    # This class does the heavy lifting of the zone provider
    class Driver
      include Vagrant::Util::Retryable
      attr_accessor :executor

      def initialize(machine)
        @logger = Log4r::Logger.new('vagrant_zones::driver')
        @machine = machine
        @executor = Executor::Exec.new
        @pfexec = if Process.uid.zero?
                    ''
                  elsif system('sudo -v')
                    'sudo'
                  else
                    'pfexec'
                  end
      end

      def state(machine)
        name = machine.name
        vm_state = execute(false, "#{@pfexec} zoneadm -z #{name} list -p | awk -F: '{ print $3 }'")
        case vm_state
        when 'running'
          :running
        when 'configured'
          :preparing
        when 'installed'
          :stopped
        when 'incomplete'
          :incomplete
        else
          :not_created
        end
      end

      # Execute System commands
      def execute(*cmd, **opts, &block)
        @executor.execute(*cmd, **opts, &block)
      end

      ## Begin installation for zone
      def install(uii)
        config = @machine.provider_config
        name = @machine.name
        case config.brand
        when 'lx'
          box = "#{@machine.data_dir}/#{@machine.config.vm.box}"
          results = execute(false, "#{@pfexec} zoneadm -z #{name} install -s #{box}")
          raise Errors::InvalidLXBrand if results.include? 'unknown brand'
        when 'bhyve'
          results = execute(false, "#{@pfexec} zoneadm -z #{name} install")
          raise Errors::InvalidbhyveBrand if results.include? 'unknown brand'
        when 'kvm' || 'illumos'
          raise Errors::NotYetImplemented
        end
        uii.info(I18n.t('vagrant_zones.installing_zone'))
        uii.info("  #{config.brand}")
      end

      ## Control the zone from inside the zone OS
      def control(uii, control)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.control')) if config.debug
        case control
        when 'rmatch(/estart'
          command = 'sudo shutdown -r'
          command = config.safe_restart unless config.safe_restart.nil?
          ssh_run_command(uii, command)
        when 'shutdown'
          command = 'sudo init 0 || true'
          command = config.safe_shutdown unless config.safe_shutdown.nil?
          ssh_run_command(uii, command)
        else
          uii.info(I18n.t('vagrant_zones.control_no_cmd'))
        end
      end

      ## Run commands over SSH instead of ZLogin
      def ssh_run_command(uii, command)
        config = @machine.provider_config
        ip = get_ip_address(uii)
        user = user(@machine)
        key = userprivatekeypath(@machine).to_s
        port = sshport(@machine).to_s
        port = 22 if sshport(@machine).to_s.nil?
        execute_return = ''
        Util::Timer.time do
          retryable(on: Errors::TimeoutError, tries: 60) do
            # If we're interrupted don't worry about waiting
            ssh_string = "#{@pfexec} ssh -o 'StrictHostKeyChecking=no' -p"
            execute_return = execute(false, %(#{ssh_string} #{port} -i #{key} #{user}@#{ip} "#{command}"))
            uii.info(I18n.t('vagrant_zones.ssh_run_command')) if config.debug
            uii.info(I18n.t('vagrant_zones.ssh_run_command') + command) if config.debug
            loop do
              break if @machine.communicate.ready?
            end
          end
        end
        execute_return
      end

      ## Function to provide console, vnc, or webvnc access
      ## Future To-Do: Should probably split this up
      def console(uii, command, ip, port, exit)
        uii.info(I18n.t('vagrant_zones.console'))
        detach = exit[:detach]
        kill = exit[:kill]
        name = @machine.name
        config = @machine.provider_config
        if port.nil?
          port = if config.consoleport.nil?
                   ''
                 else
                   config.consoleport
                 end
        end
        ipaddr = '0.0.0.0'
        ipaddr = config.consolehost if config.consolehost =~ Resolv::IPv4::Regex
        ipaddr = ip if ip =~ Resolv::IPv4::Regex
        netport = "#{ipaddr}:#{port}"
        pid = 0
        if File.exist?("#{name}.pid")
          pid = File.readlines("#{name}.pid")[0].strip
          ctype = File.readlines("#{name}.pid")[1].strip
          ts = File.readlines("#{name}.pid")[2].strip
          vmname = File.readlines("#{name}.pid")[3].strip
          nport = File.readlines("#{name}.pid")[4].strip
          uii.info("Session running with PID: #{pid} since: #{ts} as console type: #{ctype} served at: #{nport}\n") if vmname[name.to_s]
          if kill == 'yes'
            File.delete("#{name}.pid")
            Process.kill 'TERM', pid.to_i
            Process.detach pid.to_i
            uii.info('Session Terminated')
          end
        else
          case command
          when /vnc/
            run = "pfexec zadm #{command} #{netport} #{name}"
            pid = spawn(run)
            Process.wait pid if detach == 'no'
            Process.detach(pid) if detach == 'yes'
            time = Time.new.strftime('%Y-%m-%d-%H:%M:%S')
            File.write("#{name}.pid", "#{pid}\n#{command}\n#{time}\n#{name}\n#{netport}") if detach == 'yes'
            uii.info("Session running with PID: #{pid} as console type: #{command} served at: #{netport}") if detach == 'yes'
          when 'zlogin'
            run = "#{@pfexec} zadm console #{name}"
            exec(run)
          end
        end
      end

      ## Boot the Machine
      def boot(uii)
        name = @machine.name
        uii.info(I18n.t('vagrant_zones.starting_zone'))
        execute(false, "#{@pfexec} zoneadm -z #{name} boot")
      end

      # This filters the VM usage for VNIC Naming Purposes
      def vtype(config)
        case config.vm_type
        when /template/
          '1'
        when /development/
          '2'
        when /production/ || nil
          '3'
        when /firewall/
          '4'
        when /other/
          '5'
        end
      end

      # This filters the NIC Types
      def nictype(opts)
        case opts[:nictype]
        when /external/ || nil
          'e'
        when /internal/
          'i'
        when /carp/
          'c'
        when /management/
          'm'
        when /host/
          'h'
        end
      end

      # This Sanitizes the DNS Records
      def dnsservers(uii, opts)
        config = @machine.provider_config
        servers = opts['dns']
        servers = [{ 'nameserver' => '1.1.1.1' }, { 'nameserver' => '8.8.8.8' }] if opts['dns'].nil?
        uii.info(I18n.t('vagrant_zones.nsservers') + servers.to_s) if config.debug
        servers
      end

      # This Sanitizes the Mac Address
      def macaddress(uii, opts)
        config = @machine.provider_config
        regex = /^(?:[[:xdigit:]]{2}([-:]))(?:[[:xdigit:]]{2}\1){4}[[:xdigit:]]{2}$/
        mac = opts[:mac] unless opts[:mac].nil?
        mac = 'auto' unless mac.match(regex)
        uii.info(I18n.t('vagrant_zones.mac') + mac) if config.debug
        mac
      end

      # This Sanitizes the IP Address to set
      def ipaddress(uii, opts)
        config = @machine.provider_config
        ip = if opts[:ip].empty?
               nil
             else
               opts[:ip].gsub(/\t/, '')
             end
        uii.info(I18n.t('vagrant_zones.ipaddress') + ip) if config.debug
        ip
      end

      # This Sanitizes the AllowedIP Address to set for Cloudinit
      def allowedaddress(uii, opts)
        config = @machine.provider_config
        ip = ipaddress(uii, opts)
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        allowed_address = "#{ip}/#{shrtsubnet}"
        uii.info(I18n.t('vagrant_zones.allowedaddress') + allowed_address) if config.debug
        allowed_address
      end

      # This Sanitizes the VNIC Name
      def vname(uii, opts)
        config = @machine.provider_config
        vnic_name = "vnic#{nictype(opts)}#{vtype(config)}_#{config.partition_id}_#{opts[:nic_number]}"
        uii.info(I18n.t('vagrant_zones.vnic_name') + vnic_name) if config.debug
        vnic_name
      end

      ## If DHCP and Zlogin, get the IP address
      def get_ip_address(uii)
        config = @machine.provider_config
        name = @machine.name
        i = 0
        @machine.config.vm.networks.each do |_adaptertype, opts|
          nic_type = nictype(opts)
          if opts[:dhcp4] && opts[:managed]
            vnic_name = "vnic#{nic_type}#{vtype(config)}_#{config.partition_id}_#{opts[:nic_number]}"
            command = %(ip -4 addr show dev #{vnic_name} | head -n -1 | tail -1 | awk '{ print $2 }' | cut -f1 -d"/")
            PTY.spawn("pfexec zlogin -C #{name}") do |zlogin_read, zlogin_write, pid|
              responses = []
              zlogin_read.expect(/\n/) { zlogin_write.puts(command) } if i == 0
              i += 1 
              Timeout.timeout(config.clean_shutdown_time) do
                loop do
                  zlogin_read.expect(/\r\n/) { |line| responses.push line }
                  p (responses[-1]) if config.debug_boot


                  
                  ip = responses[-1].match(/((?:[0-9]{1,3}\.){3}[0-9]{1,3})/)[0]
                  
                  return nil if ip.empty?
                  return ip unless ip.empty?

                  break unless ip.empty?
                end
              end
              Process.kill('HUP', pid)
            end
          elsif (opts[:dhcp4] == false || opts[:dhcp4].nil?) && opts[:managed]
            ip = opts[:ip].to_s
            return nil if ip.empty?

            return ip.gsub(/\t/, '')
          end
        end
      end

      ## Manage Network Interfaces
      def network(uii, state)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.creating_networking_interfaces')) if state == 'create'
        @machine.config.vm.networks.each do |adaptertype, opts|
          case adaptertype.to_s
          when 'public_network'
            zonenicdel(uii, opts) if state == 'delete'
            zonecfgnicconfig(uii, opts) if state == 'config'
            zoneniccreate(uii, opts) if state == 'create'
            zonenicstpzloginsetup(uii, opts, config) if state == 'setup' && config.setup_method == 'zlogin'
          when 'private_network'
            zonenicdel(uii, opts) if state == 'delete'
            zonedhcpentriesrem(uii, opts) if state == 'delete'
            zonenatclean(uii, opts) if state == 'delete'
            etherstubdelhvnic(uii, opts) if state == 'delete'
            etherstubdelete(uii, opts) if state == 'delete'
            natnicconfig(uii, opts) if state == 'config'
            etherstub = etherstubcreate(uii, opts) if state == 'create'
            zonenatniccreate(uii, opts, etherstub) if state == 'create'
            etherstubcreatehvnic(uii, opts, etherstub) if state == 'create'
            zonenatforward(uii, opts) if state == 'create'
            zonenatentries(uii, opts) if state == 'create'
            zonedhcpentries(uii, opts) if state == 'create'
            zonedhcpcheckaddr(uii, opts) if state == 'setup'
            zonenicnatsetup(uii, opts) if state == 'setup'
          end
        end
      end

      ## Delete DHCP entries for Zones
      def zonedhcpentriesrem(uii, opts)
        config = @machine.provider_config

        ip = ipaddress(uii, opts)
        name = @machine.name
        defrouter = opts[:gateway].to_s
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        hvnic_name = "h_vnic_#{config.partition_id}_#{opts[:nic_number]}"
        mac = macaddress(uii, opts)

        ## if mac is auto, then grab NIC from VNIC
        if mac == 'auto'
          mac = ''
          cmd = "#{@pfexec} dladm show-vnic #{hvnic_name} | tail -n +2 |  awk '{ print $4 }'"
          vnicmac = execute(false, cmd.to_s)
          vnicmac.split(':').each { |x| mac += "#{format('%02x', x.to_i(16))}:" }
          mac = mac[0..-2]
        end
        uii.info(I18n.t('vagrant_zones.deconfiguring_dhcp'))
        uii.info("  #{hvnic_name}")
        broadcast = IPAddr.new(defrouter).mask(shrtsubnet).to_s
        subnet = %(subnet #{broadcast} netmask #{opts[:netmask]} { option routers #{defrouter}; })
        subnetopts = %(host #{name} { option host-name "#{name}"; hardware ethernet #{mac}; fixed-address #{ip}; })
        File.open('/etc/dhcpd.conf-temp', 'w') do |out_file|
          File.foreach('/etc/dhcpd.conf') do |entry|
            out_file.puts line unless entry == subnet || subnetopts
          end
        end
        FileUtils.mv('/etc/dhcpd.conf-temp', '/etc/dhcpd.conf')
        subawk = '{ $1=""; $2=""; sub(/^[ \\t]+/, ""); print}'
        awk = %(| awk '#{subawk}' | tr ' ' '\\n' | tr -d '"')
        cmd = 'svccfg -s dhcp:ipv4 listprop config/listen_ifnames '
        nicsused = execute(false, cmd + awk.to_s).split("\n")
        newdhcpnics = []
        nicsused.each do |nic|
          newdhcpnics << nic unless nic.to_s == hvnic_name.to_s
        end
        if newdhcpnics.empty?
          dhcpcmdnewstr = '\(\"\"\)'
        else
          dhcpcmdnewstr = '\('
          newdhcpnics.each do |nic|
            dhcpcmdnewstr += %(\\"#{nic}\\")
          end
          dhcpcmdnewstr += '\)'
        end
        execute(false, "#{@pfexec} svccfg -s dhcp:ipv4 setprop config/listen_ifnames = #{dhcpcmdnewstr}")
        execute(false, "#{@pfexec} svcadm refresh dhcp:ipv4")
        execute(false, "#{@pfexec} svcadm disable dhcp:ipv4")
        execute(false, "#{@pfexec} svcadm enable dhcp:ipv4")
      end

      def zonenatclean(uii, opts)
        vnic_name = vname(uii, opts)
        defrouter = opts[:gateway].to_s
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        broadcast = IPAddr.new(defrouter).mask(shrtsubnet).to_s
        uii.info(I18n.t('vagrant_zones.deconfiguring_nat'))
        uii.info("  #{vnic_name}")
        line1 = %(map #{opts[:bridge]} #{broadcast}/#{shrtsubnet} -> 0/32  portmap tcp/udp auto)
        line2 = %(map #{opts[:bridge]} #{broadcast}/#{shrtsubnet} -> 0/32)
        File.open('/etc/ipf/ipnat.conf-temp', 'w') do |out_file|
          File.foreach('/etc/ipf/ipnat.conf') do |entry|
            out_file.puts line unless entry == line1 || line2
          end
        end
        FileUtils.mv('/etc/ipf/ipnat.conf-temp', '/etc/ipf/ipnat.conf')
        execute(false, "#{@pfexec} svcadm refresh network/ipfilter")
      end

      def zonenicdel(uii, opts)
        vnic_name = vname(uii, opts)
        vnic_configured = execute(false, "#{@pfexec} dladm show-vnic | grep #{vnic_name} | awk '{ print $1 }' ")
        uii.info(I18n.t('vagrant_zones.removing_vnic')) if vnic_configured == vnic_name.to_s
        uii.info("  #{vnic_name}") if vnic_configured == vnic_name.to_s
        execute(false, "#{@pfexec} dladm delete-vnic #{vnic_name}") if vnic_configured == vnic_name.to_s
        uii.info(I18n.t('vagrant_zones.no_removing_vnic')) unless vnic_configured == vnic_name.to_s
      end

      ## Delete etherstubs vnic
      def etherstubdelhvnic(uii, opts)
        config = @machine.provider_config
        hvnic_name = "h_vnic_#{config.partition_id}_#{opts[:nic_number]}"
        vnic_configured = execute(false, "#{@pfexec} dladm show-vnic | grep #{hvnic_name} | awk '{ print $1 }' ")
        uii.info(I18n.t('vagrant_zones.removing_host_vnic')) if vnic_configured == hvnic_name.to_s
        uii.info("  #{hvnic_name}") if vnic_configured == hvnic_name.to_s
        execute(false, "#{@pfexec} ipadm delete-if #{hvnic_name}") if vnic_configured == hvnic_name.to_s
        execute(false, "#{@pfexec} dladm delete-vnic #{hvnic_name}") if vnic_configured == hvnic_name.to_s
        uii.info(I18n.t('vagrant_zones.no_removing_host_vnic')) unless vnic_configured == hvnic_name.to_s
      end

      ## Delete etherstubs
      def etherstubdelete(uii, opts)
        config = @machine.provider_config
        ether_name = "stub_#{config.partition_id}_#{opts[:nic_number]}"
        ether_configured = execute(false, "#{@pfexec} dladm show-etherstub | grep #{ether_name} | awk '{ print $1 }' ")
        uii.info(I18n.t('vagrant_zones.delete_ethervnic')) if ether_configured == ether_name
        uii.info("  #{ether_name}") if ether_configured == ether_name
        uii.info(I18n.t('vagrant_zones.no_delete_ethervnic')) unless ether_configured == ether_name
        execute(false, "#{@pfexec} dladm delete-etherstub #{ether_name}") if ether_configured == ether_name
      end

      ## Create etherstubs for Zones
      def etherstubcreate(uii, opts)
        config = @machine.provider_config
        ether_name = "stub_#{config.partition_id}_#{opts[:nic_number]}"
        ether_configured = execute(false, "#{@pfexec} dladm show-etherstub | grep #{ether_name} | awk '{ print $1 }' ")
        uii.info(I18n.t('vagrant_zones.creating_etherstub')) unless ether_configured == ether_name
        uii.info("  #{ether_name}") unless ether_configured == ether_name
        execute(false, "#{@pfexec} dladm create-etherstub #{ether_name}") unless ether_configured == ether_name
        ether_name
      end

      ## Create ethervnics for Zones
      def zonenatniccreate(uii, opts, etherstub)
        vnic_name = vname(uii, opts)
        mac = macaddress(uii, opts)
        uii.info(I18n.t('vagrant_zones.creating_ethervnic'))
        uii.info("  #{vnic_name}")
        execute(false, "#{@pfexec} dladm create-vnic -l #{etherstub} -m #{mac} #{vnic_name}")
      end

      ## Create Host VNIC on etherstubs for IP for Zones DHCP
      def etherstubcreatehvnic(uii, opts, etherstub)
        config = @machine.provider_config
        defrouter = opts[:gateway].to_s
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        hvnic_name = "h_vnic_#{config.partition_id}_#{opts[:nic_number]}"
        uii.info(I18n.t('vagrant_zones.creating_etherhostvnic'))
        uii.info("  #{hvnic_name}")
        execute(false, "#{@pfexec} dladm create-vnic -l #{etherstub} #{hvnic_name}")
        execute(false, "#{@pfexec} ipadm create-if #{hvnic_name}")
        execute(false, "#{@pfexec} ipadm create-addr -T static -a local=#{defrouter}/#{shrtsubnet} #{hvnic_name}/v4")
      end

      ## Setup vnics for Zones using nat/dhcp
      def zonenicnatsetup(uii, opts)
        config = @machine.provider_config
        return if config.cloud_init_enabled

        vnic_name = vname(uii, opts)
        mac = macaddress(uii, opts)
        ## if mac is auto, then grab NIC from VNIC
        if mac == 'auto'
          mac = ''
          cmd = "#{@pfexec} dladm show-vnic #{vnic_name} | tail -n +2 |  awk '{ print $4 }'"
          vnicmac = execute(false, cmd.to_s)
          vnicmac.split(':').each { |x| mac += "#{format('%02x', x.to_i(16))}:" }
          mac = mac[0..-2]
        end

        ## Code Block to Detect OS
        uii.info(I18n.t('vagrant_zones.os_detect'))
        cmd = 'uname -a'
        os_type = config.os_type
        uii.info("Zone OS configured as: #{os_type}")
        os_detected = ssh_run_command(uii, cmd.to_s)
        uii.info("Zone OS detected as: #{os_detected}")

        ## Check if Ansible is Installed to enable easier configuration
        uii.info(I18n.t('vagrant_zones.ansible_detect'))
        cmd = 'which ansible > /dev/null 2>&1 ; echo $?'
        ansible_detected = ssh_run_command(uii, cmd.to_s)
        uii.info('Ansible detected') if ansible_detected == '0'

        # Run Network Configuration
        zonenicnatsetup_netplan(uii, opts, mac) unless os_detected.to_s.match(/SunOS/)
        zonenicnatsetup_dladm(uii, opts, mac) if os_detected.to_s.match(/SunOS/)
      end

      ## Setup vnics for Zones using nat/dhcp using netplan
      def zonenicnatsetup_netplan(uii, opts, mac)
        ssh_run_command(uii, 'sudo rm -rf /etc/netplan/*.yaml')
        ip = ipaddress(uii, opts)
        defrouter = opts[:gateway].to_s
        vnic_name = vname(uii, opts)
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        servers = dnsservers(uii, opts)
        ## Begin of code block to move to Netplan function
        uii.info(I18n.t('vagrant_zones.configure_interface_using_vnic'))
        uii.info("  #{vnic_name}")
        netplan1 = %(network:\n  version: 2\n  ethernets:\n    #{vnic_name}:\n      match:\n        macaddress: #{mac}\n)
        netplan2 = %(      dhcp-identifier: mac\n      dhcp4: #{opts[:dhcp4]}\n      dhcp6: #{opts[:dhcp6]}\n)
        netplan3 = %(      set-name: #{vnic_name}\n      addresses: [#{ip}/#{shrtsubnet}]\n      gateway4: #{defrouter}\n)
        netplan4 = %(      nameservers:\n        addresses: [#{servers[0]['nameserver']} , #{servers[1]['nameserver']}] )
        netplan = netplan1 + netplan2 + netplan3 + netplan4
        cmd = "echo -e '#{netplan}' | sudo tee /etc/netplan/#{vnic_name}.yaml"
        infomessage = I18n.t('vagrant_zones.netplan_applied_static') + "/etc/netplan/#{vnic_name}.yaml"
        uii.info(infomessage) if ssh_run_command(uii, cmd)

        ## Apply the Configuration
        uii.info(I18n.t('vagrant_zones.netplan_applied')) if ssh_run_command(uii, 'sudo netplan apply')
        ## End of code block to move to Netplan function
      end

      ## Setup vnics for Zones using nat/dhcp over dladm
      def zonenicnatsetup_dladm(uii, opts, mac)
        ip = ipaddress(uii, opts)
        defrouter = opts[:gateway].to_s
        vnic_name = vname(uii, opts)
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        servers = dnsservers(uii, opts)
        uii.info(I18n.t('vagrant_zones.configure_interface_using_vnic_dladm'))
        uii.info("  #{vnic_name}")

        # loop through each phys if and run code if physif matches #{mac}
        phys_if = 'pfexec dladm show-phys -m -o LINK,ADDRESS,CLIENT | tail -n +2'
        phys_if_results = ssh_run_command(uii, phys_if).split("\n")
        device = ''
        phys_if_results.each do |entry|
          e_mac = ''
          entries = entry.strip.split
          entries[1].split(':').each { |x| e_mac += "#{format('%02x', x.to_i(16))}:" }
          e_mac = e_mac[0..-2]
          device = entries[0] if e_mac.match(/#{mac}/)
        end

        delete_if = "pfexec ipadm delete-if #{device}"
        rename_link = "pfexec dladm rename-link #{device} #{vnic_name}"
        if_create = "pfexec ipadm create-if #{vnic_name}"
        static_addr = "pfexec ipadm create-addr -T static -a #{ip}/#{shrtsubnet} #{vnic_name}/v4vagrant"
        net_cmd = "#{delete_if} && #{rename_link} && #{if_create} && #{static_addr}"
        uii.info(I18n.t('vagrant_zones.dladm_applied')) if ssh_run_command(uii, net_cmd)

        route_add = "pfexec route -p add default #{defrouter}"
        uii.info(I18n.t('vagrant_zones.dladm_route_applied')) if ssh_run_command(uii, route_add)

        ns_string = "nameserver #{servers[0]['nameserver']}\nnameserver #{servers[1]['nameserver']}"
        dns_set = "pfexec echo '#{ns_string}' | pfexec tee /etc/resolv.conf"
        uii.info(I18n.t('vagrant_zones.dladm_dns_applied')) if ssh_run_command(uii, dns_set.to_s)
      end

      ## zonecfg function for for nat Networking
      def natnicconfig(uii, opts)
        config = @machine.provider_config
        allowed_address = allowedaddress(uii, opts)
        defrouter = opts[:gateway].to_s
        vnic_name = vname(uii, opts)
        uii.info(I18n.t('vagrant_zones.nat_vnic_setup'))
        uii.info("  #{vnic_name}")
        strt = "#{@pfexec} zonecfg -z #{@machine.name} "
        cie = config.cloud_init_enabled
        case config.brand
        when 'lx'
          shrtstr1 = %(set allowed-address=#{allowed_address}; add property (name=gateway,value="#{defrouter}"); )
          shrtstr2 = %(add property (name=ips,value="#{allowed_address}"); add property (name=primary,value="true"); end;)
          execute(false, %(#{strt}set global-nic=auto; #{shrtstr1} #{shrtstr2}"))
        when 'bhyve'
          execute(false, %(#{strt}"add net; set physical=#{vnic_name}; end;")) unless cie
          execute(false, %(#{strt}"add net; set physical=#{vnic_name}; set allowed-address=#{allowed_address}; end;")) if cie
        end
      end

      ## Set NatForwarding on global interface
      def zonenatforward(uii, opts)
        config = @machine.provider_config
        hvnic_name = "h_vnic_#{config.partition_id}_#{opts[:nic_number]}"
        uii.info(I18n.t('vagrant_zones.forwarding_nat'))
        uii.info("  #{hvnic_name}")
        execute(false, "#{@pfexec} routeadm -u -e ipv4-forwarding")
        execute(false, "#{@pfexec} ipadm set-ifprop -p forwarding=on -m ipv4 #{opts[:bridge]}")
        execute(false, "#{@pfexec} ipadm set-ifprop -p forwarding=on -m ipv4 #{hvnic_name}")
      end

      ## Create nat entries for the zone
      def zonenatentries(uii, opts)
        vnic_name = vname(uii, opts)
        defrouter = opts[:gateway].to_s
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        uii.info(I18n.t('vagrant_zones.configuring_nat'))
        uii.info("  #{vnic_name}")
        broadcast = IPAddr.new(defrouter).mask(shrtsubnet).to_s
        ## Read NAT File, Check for these lines, if exist, warn, but continue
        natentries = execute(false, "#{@pfexec} cat /etc/ipf/ipnat.conf").split("\n")
        line1 = %(map #{opts[:bridge]} #{broadcast}/#{shrtsubnet} -> 0/32  portmap tcp/udp auto)
        line2 = %(map #{opts[:bridge]} #{broadcast}/#{shrtsubnet} -> 0/32)
        line1exists = false
        line2exists = false
        natentries.each do |entry|
          line1exists = true if entry == line1
          line2exists = true if entry == line2
        end
        execute(false, %(#{@pfexec} echo "#{line1}" | #{@pfexec} tee -a /etc/ipf/ipnat.conf)) unless line1exists
        execute(false, %(#{@pfexec} echo "#{line2}" | #{@pfexec} tee -a /etc/ipf/ipnat.conf)) unless line2exists
        execute(false, "#{@pfexec} svcadm refresh network/ipfilter")
        execute(false, "#{@pfexec} svcadm disable network/ipfilter")
        execute(false, "#{@pfexec} svcadm enable network/ipfilter")
      end

      ## Create dhcp entries for the zone
      def zonedhcpentries(uii, opts)
        config = @machine.provider_config
        ip = ipaddress(uii, opts)
        name = @machine.name
        vnic_name = vname(uii, opts)
        defrouter = opts[:gateway].to_s
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        hvnic_name = "h_vnic_#{config.partition_id}_#{opts[:nic_number]}"
        ## Set Mac address from VNIC
        mac = macaddress(uii, opts)
        if mac == 'auto'
          mac = ''
          cmd = "#{@pfexec} dladm show-vnic #{vnic_name} | tail -n +2 |  awk '{ print $4 }'"
          vnicmac = execute(false, cmd.to_s)
          vnicmac.split(':').each { |x| mac += "#{format('%02x', x.to_i(16))}:" }
          mac = mac[0..-2]
        end
        uii.info(I18n.t('vagrant_zones.configuring_dhcp'))
        broadcast = IPAddr.new(defrouter).mask(shrtsubnet).to_s
        dhcpentries = execute(false, "#{@pfexec} cat /etc/dhcpd.conf").split("\n")
        subnet = %(subnet #{broadcast} netmask #{opts[:netmask]} { option routers #{defrouter}; })
        subnetopts = %(host #{name} { option host-name "#{name}"; hardware ethernet #{mac}; fixed-address #{ip}; })
        subnetexists = false
        subnetoptsexists = false
        dhcpentries.each do |entry|
          subnetexists = true if entry == subnet
          subnetoptsexists = true if entry == subnetopts
        end
        execute(false, "#{@pfexec} echo '#{subnet}' | #{@pfexec} tee -a /etc/dhcpd.conf") unless subnetexists
        execute(false, "#{@pfexec} echo '#{subnetopts}' | #{@pfexec} tee -a /etc/dhcpd.conf") unless subnetoptsexists
        execute(false, "#{@pfexec} svccfg -s dhcp:ipv4 setprop config/listen_ifnames = #{hvnic_name}")
        execute(false, "#{@pfexec} svcadm refresh dhcp:ipv4")
        execute(false, "#{@pfexec} svcadm disable dhcp:ipv4")
        execute(false, "#{@pfexec} svcadm enable dhcp:ipv4")
      end

      ## Check if Address shows up in lease list /var/db/dhcpd ping address after
      def zonedhcpcheckaddr(uii, opts)
        # vnic_name = vname(uii, opts)
        # ip = ipaddress(uii, opts)
        uii.info(I18n.t('vagrant_zones.chk_dhcp_addr'))
        uii.info("  #{opts[:ip]}")
        # execute(false, "#{@pfexec} ping #{ip} ")
      end

      ## Create vnics for Zones
      def zoneniccreate(uii, opts)
        mac = macaddress(uii, opts)
        vnic_name = vname(uii, opts)
        if opts[:vlan].nil?
          uii.info(I18n.t('vagrant_zones.creating_vnic'))
          uii.info("  #{vnic_name}")
          execute(false, "#{@pfexec} dladm create-vnic -l #{opts[:bridge]} -m #{mac} #{vnic_name}")
        else
          vlan = opts[:vlan]
          uii.info(I18n.t('vagrant_zones.creating_vnic'))
          uii.info("  #{vnic_name}")
          execute(false, "#{@pfexec} dladm create-vnic -l #{opts[:bridge]} -m #{mac} -v #{vlan} #{vnic_name}")
        end
      end

      # This helps us create all the datasets for the zone
      def create_dataset(uii)
        config = @machine.provider_config
        name = @machine.name
        bootconfigs = config.boot
        datasetpath = "#{bootconfigs['array']}/#{bootconfigs['dataset']}/#{name}"
        datasetroot = "#{datasetpath}/#{bootconfigs['volume_name']}"
        sparse = '-s '
        sparse = '' unless bootconfigs['sparse']
        refres = "-o refreservation=#{bootconfigs['refreservation']}" unless bootconfigs['refreservation'].nil?
        refres = '-o refreservation=none' if bootconfigs['refreservation'] == 'none' || bootconfigs['refreservation'].nil?
        uii.info(I18n.t('vagrant_zones.begin_create_datasets'))
        ## Create Boot Volume
        case config.brand
        when 'lx'
          uii.info(I18n.t('vagrant_zones.lx_zone_dataset'))
          uii.info("  #{datasetroot}")
          execute(false, "#{@pfexec} zfs create -o zoned=on -p #{datasetroot}")
        when 'bhyve'
          ## Create root dataset
          uii.info(I18n.t('vagrant_zones.bhyve_zone_dataset_root'))
          uii.info("  #{datasetpath}")
          execute(false, "#{@pfexec} zfs create #{datasetpath}")

          # Create boot volume
          cinfo = "#{datasetroot}, #{bootconfigs['size']}"
          uii.info(I18n.t('vagrant_zones.bhyve_zone_dataset_boot'))
          uii.info("  #{cinfo}")
          execute(false, "#{@pfexec} zfs create #{sparse} #{refres} -V #{bootconfigs['size']} #{datasetroot}")

          ## Import template to boot volume
          commandtransfer = "#{@pfexec} pv -n #{@machine.box.directory.join('box.zss')} | #{@pfexec} zfs recv -u -v -F #{datasetroot}"
          uii.info(I18n.t('vagrant_zones.template_import_path'))
          uii.info("  #{@machine.box.directory.join('box.zss')}")
          Util::Subprocess.new commandtransfer do |_stdout, stderr, _thread|
            uii.rewriting do |uiprogress|
              uiprogress.clear_line
              uiprogress.info(I18n.t('vagrant_zones.importing_box_image_to_disk') + "#{datasetroot} ", new_line: false)
              uiprogress.report_progress(stderr, 100, false)
            end
          end
          uii.clear_line

          uii.info(I18n.t('vagrant_zones.template_import_path_set_size'))
          execute(false, "#{@pfexec} zfs set volsize=#{bootconfigs['size']} #{datasetroot}")

        when 'illumos' || 'kvm'
          raise Errors::NotYetImplemented
        else
          raise Errors::InvalidBrand
        end
        ## Create Additional Disks
        return if config.additional_disks.nil?

        config.additional_disks.each do |disk|
          shrtpath = "#{disk['array']}/#{disk['dataset']}/#{name}"
          dataset = "#{shrtpath}/#{disk['volume_name']}"
          sparse = '-s '
          sparse = '' unless disk['sparse']
          refres = "-o refreservation=#{bootconfigs['refreservation']}" unless bootconfigs['refreservation'].nil?
          refres = '-o refreservation=none' if bootconfigs['refreservation'] == 'none' || bootconfigs['refreservation'].nil?
          ## If the root data set doesn't exist create it
          addsrtexists = execute(false, "#{@pfexec} zfs list | grep #{shrtpath} | awk '{ print $1 }' | head -n 1 || true")
          cinfo = shrtpath.to_s
          uii.info(I18n.t('vagrant_zones.bhyve_zone_dataset_additional_volume_root')) unless addsrtexists == shrtpath.to_s
          uii.info("  #{cinfo}") unless addsrtexists == shrtpath.to_s
          ## Create the Additional volume
          execute(false, "#{@pfexec} zfs create #{shrtpath}") unless addsrtexists == shrtpath.to_s
          cinfo = "#{dataset}, #{disk['size']}"
          uii.info(I18n.t('vagrant_zones.bhyve_zone_dataset_additional_volume'))
          uii.info("  #{cinfo}")
          execute(false, "#{@pfexec} zfs create #{sparse} #{refres} -V #{disk['size']} #{dataset}")
        end
      end

      # This helps us delete any associated datasets of the zone
      def delete_dataset(uii)
        config = @machine.provider_config
        name = @machine.name
        # datadir = machine.data_dir
        bootconfigs = config.boot
        datasetpath = "#{bootconfigs['array']}/#{bootconfigs['dataset']}/#{name}"
        datasetroot = "#{datasetpath}/#{bootconfigs['volume_name']}"
        uii.info(I18n.t('vagrant_zones.delete_disks'))

        ## Check if Boot Dataset exists
        zp = datasetpath.delete_prefix('/').to_s
        dataset_boot_exists = execute(false, "#{@pfexec} zfs list | grep #{datasetroot} | awk '{ print $1 }' || true")

        ## Destroy Boot dataset
        uii.info(I18n.t('vagrant_zones.destroy_dataset')) if dataset_boot_exists == datasetroot.to_s
        uii.info("  #{datasetroot}") if dataset_boot_exists == datasetroot.to_s
        execute(false, "#{@pfexec} zfs destroy -r #{datasetroot}") if dataset_boot_exists == datasetroot.to_s
        ## Insert Error Checking Here in case disk is busy
        uii.info(I18n.t('vagrant_zones.boot_dataset_nil')) unless dataset_boot_exists == datasetroot.to_s

        ## Destroy Additional Disks
        unless config.additional_disks.nil?
          disks = config.additional_disks
          disks.each do |disk|
            diskpath = "#{disk['array']}/#{disk['dataset']}/#{name}"
            addataset = "#{diskpath}/#{disk['volume_name']}"
            cinfo = addataset.to_s
            dataset_exists = execute(false, "#{@pfexec} zfs list | grep #{addataset} | awk '{ print $1 }' || true")
            uii.info(I18n.t('vagrant_zones.bhyve_zone_dataset_additional_volume_destroy')) if dataset_exists == addataset
            uii.info("  #{cinfo}") if dataset_exists == addataset
            execute(false, "#{@pfexec} zfs destroy -r #{addataset}") if dataset_exists == addataset
            uii.info(I18n.t('vagrant_zones.additional_dataset_nil')) unless dataset_exists == addataset
            cinfo = diskpath.to_s
            addsrtexists = execute(false, "#{@pfexec} zfs list | grep #{diskpath} | awk '{ print $1 }' | head -n 1 || true")
            uii.info(I18n.t('vagrant_zones.addtl_volume_destroy_root')) if addsrtexists == diskpath && addsrtexists != zp.to_s
            uii.info("  #{cinfo}") if addsrtexists == diskpath && addsrtexists != zp.to_s
            execute(false, "#{@pfexec} zfs destroy -r #{diskpath}") if addsrtexists == diskpath && addsrtexists != zp.to_s
          end
        end

        ## Check if root dataset exists
        dataset_root_exists = execute(false, "#{@pfexec} zfs list | grep #{zp} | awk '{ print $1 }' | grep -v path || true")
        uii.info(I18n.t('vagrant_zones.destroy_root_dataset')) if dataset_root_exists == zp.to_s
        uii.info("  #{zp}") if dataset_root_exists == zp.to_s
        execute(false, "#{@pfexec} zfs destroy -r #{zp}") if dataset_root_exists == zp.to_s
        uii.info(I18n.t('vagrant_zones.root_dataset_nil')) unless dataset_root_exists == zp.to_s
      end

      ## zonecfg function for bhyve
      def zonecfgbhyve(uii, name, config, zcfg)
        return unless config.brand == 'bhyve'

        bootconfigs = config.boot
        datasetpath = "#{bootconfigs['array']}/#{bootconfigs['dataset']}/#{name}"
        datasetroot = "#{datasetpath}/#{bootconfigs['volume_name']}"
        execute(false, %(#{zcfg}"create ; set zonepath=/#{datasetpath}/path"))
        execute(false, %(#{zcfg}"set brand=#{config.brand}"))
        execute(false, %(#{zcfg}"set autoboot=#{config.autoboot}"))
        execute(false, %(#{zcfg}"set ip-type=exclusive"))
        execute(false, %(#{zcfg}"add attr; set name=acpi; set value=#{config.acpi}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=ram; set value=#{config.memory}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=bootrom; set value=#{firmware(uii)}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=hostbridge; set value=#{config.hostbridge}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=diskif; set value=#{config.diskif}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=netif; set value=#{config.netif}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=bootdisk; set value=#{datasetroot.delete_prefix('/')}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=type; set value=#{config.os_type}; set type=string; end;"))
        execute(false, %(#{zcfg}"add attr; set name=xhci; set value=#{config.xhci_enabled}; set type=string; end;"))
        execute(false, %(#{zcfg}"add device; set match=/dev/zvol/rdsk/#{datasetroot}; end;"))
        uii.info(I18n.t('vagrant_zones.bhyve_zone_config_gen'))
      end

      ## zonecfg function for lx
      def zonecfglx(uii, name, config, zcfg)
        return unless config.brand == 'lx'

        datasetpath = "#{config.boot['array']}/#{config.boot['dataset']}/#{name}"
        datasetroot = "#{datasetpath}/#{config.boot['volume_name']}"
        uii.info(I18n.t('vagrant_zones.lx_zone_config_gen'))
        @machine.config.vm.networks.each do |adaptertype, opts|
          next unless adaptertype.to_s == 'public_network'

          @ip = opts[:ip].to_s
          cinfo = "#{opts[:ip]}/#{opts[:netmask]}"
          @network = NetAddr.parse_net(cinfo)
          @defrouter = opts[:gateway]
        end
        execute(false, %(#{zcfg}"create ; set zonepath=/#{datasetpath}/path"))
        execute(false, %(#{zcfg}"set brand=#{config.brand}"))
        execute(false, %(#{zcfg}"set autoboot=#{config.autoboot}"))
        execute(false, %(#{zcfg}"add attr; set name=kernel-version; set value=#{config.kernel}; set type=string; end;"))
        cmss = ' add capped-memory; set physical='
        execute(false, %(#{zcfg + cmss}"#{config.memory}; set swap=#{config.kernel}; set locked=#{config.memory}; end;"))
        execute(false, %(#{zcfg}"add dataset; set name=#{datasetroot}; end;"))
        execute(false, %(#{zcfg}"set max-lwps=2000"))
      end

      ## zonecfg function for KVM
      def zonecfgkvm(uii, name, config, _zcfg)
        return unless config.brand == 'kvm'

        bootconfigs = config.boot
        config = @machine.provider_config
        datasetpath = "#{bootconfigs['array']}/#{bootconfigs['dataset']}/#{name}"
        datasetroot = "#{datasetpath}/#{bootconfigs['volume_name']}"
        uii.info(datasetroot) if config.debug
        ###### RESERVED ######
      end

      ## zonecfg function for Shared Disk Configurations
      def zonecfgshareddisks(uii, _name, config, zcfg)
        return unless config.shared_disk_enabled

        uii.info(I18n.t('vagrant_zones.setting_alt_shared_disk_configurations') + path.path)
        execute(false, %(#{zcfg}"add fs; set dir=/vagrant; set special=#{config.shared_dir}; set type=lofs; end;"))
      end

      ## zonecfg function for CPU Configurations
      def zonecfgcpu(uii, _name, config, zcfg)
        uii.info(I18n.t('vagrant_zones.zonecfgcpu')) if config.debug
        if config.cpu_configuration == 'simple' && (config.brand == 'bhyve' || config.brand == 'kvm')
          execute(false, %(#{zcfg}"add attr; set name=vcpus; set value=#{config.cpus}; set type=string; end;"))
        elsif config.cpu_configuration == 'complex' && (config.brand == 'bhyve' || config.brand == 'kvm')
          hash = config.complex_cpu_conf[0]
          cstring = %(sockets=#{hash['sockets']},cores=#{hash['cores']},threads=#{hash['threads']})
          execute(false, %(#{zcfg}'add attr; set name=vcpus; set value="#{cstring}"; set type=string; end;'))
        end
      end

      ## zonecfg function for CDROM Configurations
      def zonecfgcdrom(uii, _name, config, zcfg)
        return if config.cdroms.nil?

        cdroms = config.cdroms
        cdrun = 0
        cdroms.each do |cdrom|
          cdname = 'cdrom'
          uii.info(I18n.t('vagrant_zones.setting_cd_rom_configurations'))
          uii.info("  #{cdrom['path']}")
          cdname += cdrun.to_s if cdrun.positive?
          cdrun += 1
          shrtstrng = 'set type=lofs; add options nodevices; add options ro; end;'
          execute(false, %(#{zcfg}"add attr; set name=#{cdname}; set value=#{cdrom['path']}; set type=string; end;"))
          execute(false, %(#{zcfg}"add fs; set dir=#{cdrom['path']}; set special=#{cdrom['path']}; #{shrtstrng}"))
        end
      end

      ## zonecfg function for PCI Configurations
      def zonecfgpci(uii, _name, config, _zcfg)
        return if config.debug

        uii.info(I18n.t('vagrant_zones.pci')) if config.debug
        ##### RESERVED
      end

      ## zonecfg function for AdditionalDisks
      def zonecfgadditionaldisks(uii, name, config, zcfg)
        return if config.additional_disks.nil?

        diskrun = 0
        config.additional_disks.each do |disk|
          diskname = 'disk'
          dset = "#{disk['array']}/#{disk['dataset']}/#{name}/#{disk['volume_name']}"
          cinfo = "#{dset}, #{disk['size']}"
          uii.info(I18n.t('vagrant_zones.setting_additional_disks_configurations'))
          uii.info("  #{cinfo}")
          diskname += diskrun.to_s if diskrun.positive?
          diskrun += 1
          execute(false, %(#{zcfg}"add device; set match=/dev/zvol/rdsk/#{dset}; end;"))
          execute(false, %(#{zcfg}"add attr; set name=#{diskname}; set value=#{dset}; set type=string; end;"))
        end
      end

      ## zonecfg function for Console Access
      def zonecfgconsole(uii, _name, config, zcfg)
        return if config.console.nil? || config.console == 'disabled'

        port = if %w[console].include?(config.console) && config.consoleport.nil?
                 'socket,/tmp/vm.com1'
               elsif %w[webvnc].include?(config.console) || %w[vnc].include?(config.console)
                 config.console = 'vnc'
                 'on'
               else
                 config.consoleport
               end
        port += ',wait' if config.console_onboot
        cp = config.consoleport
        ch = config.consolehost
        cb = config.console_onboot
        ct = config.console
        cinfo = "Console type: #{ct}, State: #{port}, Port: #{cp},  Host: #{ch}, Wait: #{cb}"
        uii.info(I18n.t('vagrant_zones.setting_console_access'))
        uii.info("  #{cinfo}")
        execute(false, %(#{zcfg}"add attr; set name=#{ct}; set value=#{port}; set type=string; end;"))
      end

      ## zonecfg function for Cloud-init
      def zonecfgcloudinit(uii, _name, config, zcfg)
        return unless config.cloud_init_enabled

        cloudconfig = 'on' if config.cloud_init_conf.nil?
        cloudconfig = config.cloud_init_conf.to_s unless config.cloud_init_conf.nil?

        uii.info(I18n.t('vagrant_zones.setting_cloud_init_access'))
        execute(false, %(#{zcfg}"add attr; set name=cloud-init; set value=#{cloudconfig}; set type=string; end;"))

        ccid = config.cloud_init_dnsdomain
        uii.info(I18n.t('vagrant_zones.setting_cloud_dnsdomain')) unless ccid.nil?
        uii.info("  #{ccid}") unless ccid.nil?
        execute(false, %(#{zcfg}"add attr; set name=dns-domain; set value=#{ccid}; set type=string; end;")) unless ccid.nil?

        ccip = config.cloud_init_password
        uii.info(I18n.t('vagrant_zones.setting_cloud_password')) unless ccip.nil?
        uii.info("  #{ccip}") unless ccip.nil?
        execute(false, %(#{zcfg}"add attr; set name=password; set value=#{ccip}; set type=string; end;")) unless ccip.nil?

        cclir = config.dns
        dservers = []
        cclir['dns'].each do |ns|
          dservers.append(ns['nameserver'])
        end
        uii.info(I18n.t('vagrant_zones.setting_cloud_resolvers')) unless dservers.nil?
        uii.info("  #{dservers}") unless dservers.nil?
        execute(false, %(#{zcfg}"add attr; set name=resolvers; set value=#{dservers}; set type=string; end;")) unless dservers.nil?

        ccisk = config.cloud_init_sshkey
        uii.info(I18n.t('vagrant_zones.setting_cloud_ssh_key')) unless ccisk.nil?
        uii.info("  #{ccisk}") unless ccisk.nil?
        execute(false, %(#{zcfg}"add attr; set name=sshkey; set value=#{ccisk}; set type=string; end;")) unless ccisk.nil?
      end

      ## zonecfg function for for Networking
      def zonecfgnicconfig(uii, opts)
        allowed_address = allowedaddress(uii, opts)
        defrouter = opts[:gateway].to_s
        vnic_name = vname(uii, opts)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.vnic_setup'))
        uii.info("  #{vnic_name}")
        strt = "#{@pfexec} zonecfg -z #{@machine.name} "
        cie = config.cloud_init_enabled
        aa = config.allowed_address
        case config.brand
        when 'lx'
          shrtstr1 = %(set allowed-address=#{allowed_address}; add property (name=gateway,value="#{defrouter}"); )
          shrtstr2 = %(add property (name=ips,value="#{allowed_address}"); add property (name=primary,value="true"); end;)
          execute(false, %(#{strt}set global-nic=auto; #{shrtstr1} #{shrtstr2}"))
        when 'bhyve'
          execute(false, %(#{strt}"add net; set physical=#{vnic_name}; end;")) unless cie
          execute(false, %(#{strt}"add net; set physical=#{vnic_name}; set allowed-address=#{allowed_address}; end;")) if cie && aa
          execute(false, %(#{strt}"add net; set physical=#{vnic_name}; end;")) if cie && !aa
        end
      end

      # This helps us set the zone configurations for the zone
      def zonecfg(uii)
        name = @machine.name
        config = @machine.provider_config
        zcfg = "#{@pfexec} zonecfg -z #{name} "
        ## Create LX zonecfg
        zonecfglx(uii, name, config, zcfg)
        ## Create bhyve zonecfg
        zonecfgbhyve(uii, name, config, zcfg)
        ## Create kvm zonecfg
        zonecfgkvm(uii, name, config, zcfg)
        ## Shared Disk Configurations
        zonecfgshareddisks(uii, name, config, zcfg)
        ## CPU Configurations
        zonecfgcpu(uii, name, config, zcfg)
        ## CDROM Configurations
        zonecfgcdrom(uii, name, config, zcfg)
        ### Passthrough PCI Devices
        zonecfgpci(uii, name, config, zcfg)
        ## Additional Disk Configurations
        zonecfgadditionaldisks(uii, name, config, zcfg)
        ## Console access configuration
        zonecfgconsole(uii, name, config, zcfg)
        ## Cloud-init settings
        zonecfgcloudinit(uii, name, config, zcfg)
        ## Nic Configurations
        network(uii, 'config')
      end

      ## Setup vnics for Zones using Zlogin
      def zonenicstpzloginsetup(uii, opts, config)
        vnic_name = vname(uii, opts)
        mac = macaddress(uii, opts)
        ## if mac is auto, then grab NIC from VNIC
        if mac == 'auto'
          mac = ''
          cmd = "#{@pfexec} dladm show-vnic #{vnic_name} | tail -n +2 |  awk '{ print $4 }'"
          vnicmac = execute(false, cmd.to_s)
          vnicmac.split(':').each { |x| mac += "#{format('%02x', x.to_i(16))}:" }
          mac = mac[0..-2]
        end

        zoneniczloginsetup_windows(uii, opts, mac) if config.os_type.to_s.match(/windows/)
        zoneniczloginsetup_netplan(uii, opts, mac) unless config.os_type.to_s.match(/windows/)
      end

      ## This setups the Netplan based OS Networking via Zlogin
      def zoneniczloginsetup_netplan(uii, opts, mac)
        zlogin(uii, 'rm -rf /etc/netplan/*.yaml') if (opts[:nic_number]).zero?
        ip = ipaddress(uii, opts)
        vnic_name = vname(uii, opts)
        servers = dnsservers(uii, opts)
        shrtsubnet = IPAddr.new(opts[:netmask].to_s).to_i.to_s(2).count('1').to_s
        defrouter = opts[:gateway].to_s
        uii.info(I18n.t('vagrant_zones.configure_interface_using_vnic'))
        uii.info("  #{vnic_name}")
        netplan1 = %(network:\n  version: 2\n  ethernets:\n    #{vnic_name}:\n      match:\n        macaddress: #{mac}\n)
        netplan2 = ''
        netplan2 = %(      dhcp-identifier: mac\n      dhcp4: #{opts[:dhcp4]}\n      dhcp6: #{opts[:dhcp6]}\n) if opts[:dhcp4]
        netplan3 = %(      set-name: #{vnic_name}\n      addresses: [#{ip}/#{shrtsubnet}]\n)
        netplan3 = %(      set-name: #{vnic_name}\n) if opts[:dhcp4]
        netplan4 = %(      gateway4: #{defrouter}\n)
        netplan5 = %(      nameservers:\n        addresses: [#{servers[0]['nameserver']} , #{servers[1]['nameserver']}] )
        netplan = netplan1 + netplan2 + netplan3 + netplan5 if opts[:gateway].nil?
        netplan = netplan1 + netplan2 + netplan3 + netplan4 + netplan5 unless opts[:gateway].nil?
        cmd = "echo '#{netplan}' > /etc/netplan/#{vnic_name}.yaml"
        infomessage = I18n.t('vagrant_zones.netplan_applied_static') + "/etc/netplan/#{vnic_name}.yaml"
        uii.info(infomessage) if zlogin(uii, cmd)
        ## Apply the Configuration
        uii.info(I18n.t('vagrant_zones.netplan_applied')) if zlogin(uii, 'netplan apply')
      end

      # This ensures the zone is safe to boot
      def check_zone_support(uii)
        uii.info(I18n.t('vagrant_zones.preflight_checks'))
        config = @machine.provider_config
        ## Detect if Virtualbox is Running
        ## LX, KVM, and Bhyve cannot run conncurently with Virtualbox:
        ### https://illumos.topicbox-beta.com/groups/omnios-discuss/Tce3bbd08cace5349-M5fc864e9c1a7585b94a7c080
        uii.info(I18n.t('vagrant_zones.vbox_run_check'))
        result = execute(true, "#{@pfexec} VBoxManage list runningvms")
        raise Errors::VirtualBoxRunningConflictDetected if result.zero?

        ## https://man.omnios.org/man5/brands
        case config.brand
        when 'lx'
          uii.info(I18n.t('vagrant_zones.lx_check'))
        when 'ipkg'
          uii.info(I18n.t('vagrant_zones.ipkg_check'))
        when 'lipkg'
          uii.info(I18n.t('vagrant_zones.lipkg_check'))
        when 'pkgsrc'
          uii.info(I18n.t('vagrant_zones.pkgsrc_check'))
        when 'sparse'
          uii.info(I18n.t('vagrant_zones.sparse_check'))
        when 'kvm'
          ## https://man.omnios.org/man5/kvm
          uii.info(I18n.t('vagrant_zones.kvm_check'))
        when 'illumos'
          uii.info(I18n.t('vagrant_zones.illumos_check'))
        when 'bhyve'
          ## https://man.omnios.org/man5/bhyve
          ## Check for bhhwcompat
          result = execute(true, "#{@pfexec} test -f /usr/sbin/bhhwcompat ; echo $?")
          if result == 1
            bhhwcompaturl = 'https://downloads.omnios.org/misc/bhyve/bhhwcompat'
            execute(true, "#{@pfexec} curl -o /usr/sbin/bhhwcompat #{bhhwcompaturl} && #{@pfexec} chmod +x /usr/sbin/bhhwcompat")
            result = execute(true, "#{@pfexec} test -f /usr/sbin/bhhwcompat ; echo $?")
            raise Errors::MissingCompatCheckTool if result.zero?
          end

          # Check whether OmniOS version is lower than r30
          cutoff_release = '1510380'
          cutoff_release = cutoff_release[0..-2].to_i
          uii.info(I18n.t('vagrant_zones.bhyve_check'))
          uii.info("  #{cutoff_release}")
          release = File.open('/etc/release', &:readline)
          release = release.scan(/\w+/).values_at(-1)
          release = release[0][1..-2].to_i
          raise Errors::SystemVersionIsTooLow if release < cutoff_release

          # Check Bhyve compatability
          uii.info(I18n.t('vagrant_zones.bhyve_compat_check'))
          result = execute(false, "#{@pfexec} bhhwcompat -s")
          raise Errors::MissingBhyve if result.length == 1
        end
      end

      # This helps us set up the networking of the VM
      def setup(uii)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.network_setup')) if config.brand && !config.cloud_init_enabled
        network(uii, 'setup') if config.brand == 'bhyve' && !config.cloud_init_enabled
      end

      ## this allows us a terminal to pass commands and manipulate the VM OS via serial/tty, I want to redo this at some point
      def zloginboot(uii)
        name = @machine.name
        config = @machine.provider_config
        lcheck = config.lcheck
        lcheck = ':~' if config.lcheck.nil?
        alcheck = config.alcheck
        alcheck = 'login:' if config.alcheck.nil?
        bstring = ' OK ' if config.booted_string.nil?
        bstring = config.booted_string unless config.booted_string.nil?
        zunlockboot = 'Importing ZFS root pool'
        zunlockboot = config.zunlockboot unless config.zunlockboot.nil?
        zunlockbootkey = config.zunlockbootkey unless config.zunlockbootkey.nil?
        pcheck = 'Password:'
        uii.info(I18n.t('vagrant_zones.automated-zlogin'))
        PTY.spawn("pfexec zlogin -C #{name}") do |zlogin_read, zlogin_write, pid|
          Timeout.timeout(config.setup_wait) do
            rsp = []

            loop do
              zlogin_read.expect(/\r\n/) { |line| rsp.push line }
              uii.info(rsp[-1]) if config.debug_boot
              sleep(2) if rsp[-1].to_s.match(/#{zunlockboot}/)
              zlogin_write.printf("#{zunlockbootkey}\n") if rsp[-1].to_s.match(/#{zunlockboot}/)
              zlogin_write.printf("\n") if rsp[-1].to_s.match(/#{zunlockboot}/)
              uii.info(I18n.t('vagrant_zones.automated-zbootunlock')) if rsp[-1].to_s.match(/#{zunlockboot}/)
              sleep(15) if rsp[-1].to_s.match(/#{bstring}/)
              zlogin_write.printf("\n") if rsp[-1].to_s.match(/#{bstring}/)
              break if rsp[-1].to_s.match(/#{bstring}/)
            end

            if zlogin_read.expect(/#{alcheck}/)
              uii.info(I18n.t('vagrant_zones.automated-zlogin-user'))
              zlogin_write.printf("#{user(@machine)}\n")
              sleep(config.login_wait)
            end

            if zlogin_read.expect(/#{pcheck}/)
              uii.info(I18n.t('vagrant_zones.automated-zlogin-pass'))
              zlogin_write.printf("#{vagrantuserpass(@machine)}\n")
              sleep(config.login_wait)
            end

            zlogin_write.printf("\n")
            if zlogin_read.expect(/#{lcheck}/)
              uii.info(I18n.t('vagrant_zones.automated-zlogin-root'))
              zlogin_write.printf("sudo su\n")
              sleep(config.login_wait)
              Process.kill('HUP', pid)
            end
          end
        end
      end

      def natloginboot(uii, metrics, interrupted)
        metrics ||= {}
        metrics['instance_dhcp_ssh_time'] = Util::Timer.time do
          retryable(on: Errors::TimeoutError, tries: 60) do
            # If we're interrupted don't worry about waiting
            next if interrupted

            loop do
              break if interrupted
              break if @machine.communicate.ready?
            end
          end
        end
        uii.info(I18n.t('vagrant_zones.dhcp_boot_ready') + " in #{metrics['instance_dhcp_ssh_time']} Seconds")
      end

      # This helps up wait for the boot of the vm by using zlogin
      def waitforboot(uii, metrics, interrupted)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.wait_for_boot'))
        case config.brand
        when 'bhyve'
          return if config.cloud_init_enabled

          zloginboot(uii) if config.setup_method == 'zlogin' && !config.os_type.to_s.match(/windows/)
          zlogin_win_boot(uii) if config.setup_method == 'zlogin' && config.os_type.to_s.match(/windows/)
          natloginboot(uii, metrics, interrupted) if config.setup_method == 'dhcp'
        when 'lx'
          unless user_exists?(uii, config.vagrant_user)
            # zlogincommand(uii, %('echo nameserver 1.1.1.1 >> /etc/resolv.conf'))
            # zlogincommand(uii, %('echo nameserver 1.0.0.1 >> /etc/resolv.conf'))
            zlogincommand(uii, 'useradd -m -s /bin/bash -U vagrant')
            zlogincommand(uii, 'echo "vagrant ALL=(ALL:ALL) NOPASSWD:ALL" \\> /etc/sudoers.d/vagrant')
            zlogincommand(uii, 'mkdir -p /home/vagrant/.ssh')
            key_url = 'https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub'
            zlogincommand(uii, "curl #{key_url} -O /home/vagrant/.ssh/authorized_keys")

            id_rsa = 'https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant'
            command = "#{@pfexec} curl #{id_rsa} -O id_rsa"
            Util::Subprocess.new command do |_stdout, stderr, _thread|
              uii.rewriting do |uisp|
                uisp.clear_line
                uisp.info(I18n.t('vagrant_zones.importing_vagrant_key'), new_line: false)
                uisp.report_progress(stderr, 100, false)
              end
            end
            uii.clear_line
            zlogincommand(uii, 'chown -R vagrant:vagrant /home/vagrant/.ssh')
            zlogincommand(uii, 'chmod 600 /home/vagrant/.ssh/authorized_keys')
          end
        end
      end

      ## This setups the Windows Networking via Zlogin
      def zoneniczloginsetup_windows(uii, opts, _mac)
        ip = ipaddress(uii, opts)
        vnic_name = vname(uii, opts)
        servers = dnsservers(uii, opts)
        defrouter = opts[:gateway].to_s
        uii.info(I18n.t('vagrant_zones.configure_win_interface_using_vnic'))
        sleep(60)

        ## Insert code to get the list of interfaces by mac address in order
        ## to set the proper VNIC name if using multiple adapters
        rename_adapter = %(netsh interface set interface name = "Ethernet" newname = "#{vnic_name}")
        cmd = %(netsh interface ipv4 set address name="#{vnic_name}" static #{ip} #{opts[:netmask]} #{defrouter})
        dns1 = %(netsh int ipv4 set dns name="#{vnic_name}" static #{servers[0]['nameserver']} primary validate=no)
        dns2 = %(netsh int ipv4 add dns name="#{vnic_name}" #{servers[1]['nameserver']} index=2 validate=no)

        uii.info(I18n.t('vagrant_zones.win_applied_rename_adapter')) if zlogin(uii, rename_adapter)
        uii.info(I18n.t('vagrant_zones.win_applied_static')) if zlogin(uii, cmd)
        uii.info(I18n.t('vagrant_zones.win_applied_dns1')) if zlogin(uii, dns1)
        uii.info(I18n.t('vagrant_zones.win_applied_dns2')) if zlogin(uii, dns2)
      end

      def zlogin_win_boot(uii)
        ## use Windows SAC to setup networking
        name = @machine.name
        config = @machine.provider_config
        event_cmd_available = 'EVENT: The CMD command is now available'
        event_channel_created = 'EVENT:   A new channel has been created'
        channel_access_prompt = 'Use any other key to view this channel'
        cmd = 'system32>'
        uii.info(I18n.t('vagrant_zones.automated-windows-zlogin'))
        PTY.spawn("pfexec zlogin -C #{name}") do |zlogin_read, zlogin_write, pid|
          Timeout.timeout(config.setup_wait) do
            uii.info(I18n.t('vagrant_zones.windows_skip_first_boot')) if zlogin_read.expect(/#{event_cmd_available}/)
            sleep(3)
            if zlogin_read.expect(/#{event_cmd_available}/)
              uii.info(I18n.t('vagrant_zones.windows_start_cmd'))
              zlogin_write.printf("cmd\n")
            end
            if zlogin_read.expect(/#{event_channel_created}/)
              uii.info(I18n.t('vagrant_zones.windows_access_session'))
              zlogin_write.printf("\e\t")
            end
            if zlogin_read.expect(/#{channel_access_prompt}/)
              uii.info(I18n.t('vagrant_zones.windows_access_session_presskey'))
              zlogin_write.printf('o')
            end
            if zlogin_read.expect(/Username:/)
              uii.info(I18n.t('vagrant_zones.windows_enter_username'))
              zlogin_write.printf("#{user(@machine)}\n")
            end
            if zlogin_read.expect(/Domain/)
              uii.info(I18n.t('vagrant_zones.windows_enter_domain'))
              zlogin_write.printf("\n")
            end
            if zlogin_read.expect(/Password/)
              uii.info(I18n.t('vagrant_zones.windows_enter_password'))
              zlogin_write.printf("#{vagrantuserpass(@machine)}\n")
            end
            if zlogin_read.expect(/#{cmd}/)
              uii.info(I18n.t('vagrant_zones.windows_cmd_accessible'))
              sleep(5)
              Process.kill('HUP', pid)
            end
          end
        end
      end

      # This gives us a console to the VM to issue commands
      def zlogin(uii, cmd)
        name = @machine.name
        config = @machine.provider_config
        rsp = []
        PTY.spawn("pfexec zlogin -C #{name}") do |zread, zwrite, pid|
          Timeout.timeout(config.setup_wait) do
            error_check = "echo \"Error Code: $?\"\n"
            error_check = "echo Error Code: %%ERRORLEVEL%% \r\n\r\n" if config.os_type.to_s.match(/windows/)
            runonce = true
            loop do
              zread.expect(/\n/) { |line| rsp.push line }
              puts(rsp[-1].to_s) if config.debug
              zwrite.printf("#{cmd}\r\n") if runonce
              zwrite.printf(error_check.to_s) if runonce
              runonce = false
              break if rsp[-1].to_s.match(/Error Code: 0/)

              em = "#{cmd} \nFailed with ==> #{rsp[-1]}"
              uii.info(I18n.t('vagrant_zones.console_failed') + em) if rsp[-1].to_s.match(/Error Code: \b(?!0\b)\d{1,4}\b/)
              raise Errors::ConsoleFailed if rsp[-1].to_s.match(/Error Code: \b(?!0\b)\d{1,4}\b/)
            end
          end
          Process.kill('HUP', pid)
        end
      end

      # This checks if the user exists on the VM, usually for LX zones
      def user_exists?(uii, user = 'vagrant')
        name = @machine.name
        config = @machine.provider_config
        ret = execute(true, "#{@pfexec} zlogin #{name} id -u #{user}")
        uii.info(I18n.t('vagrant_zones.userexists')) if config.debug
        return true if ret.zero?

        false
      end

      # This gives the user a terminal console
      def zlogincommand(uii, cmd)
        name = @machine.name
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.zonelogincmd')) if config.debug
        execute(false, "#{@pfexec} zlogin #{name} #{cmd}")
      end

      # This filters the vagrantuser
      def user(machine)
        config = machine.provider_config
        user = config.vagrant_user unless config.vagrant_user.nil?
        user = 'vagrant' if config.vagrant_user.nil?
        user
      end

      # This filters the userprivatekeypath
      def userprivatekeypath(machine)
        config = machine.provider_config
        userkey = config.vagrant_user_private_key_path.to_s
        if config.vagrant_user_private_key_path.to_s.nil?
          id_rsa = 'https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant'
          file = './id_rsa'
          command = "#{@pfexec} curl #{id_rsa} -O #{file}"
          Util::Subprocess.new command do |_stdout, stderr, _thread|
            uii.rewriting do |uipkp|
              uipkp.clear_line
              uipkp.info(I18n.t('vagrant_zones.importing_vagrant_key'), new_line: false)
              uipkp.report_progress(stderr, 100, false)
            end
          end
          uii.clear_line
          userkey = './id_rsa'
        end
        userkey
      end

      # This filters the sshport
      def sshport(machine)
        config = machine.provider_config
        sshport = '22'
        sshport = config.sshport.to_s unless config.sshport.to_s.nil? || config.sshport.to_i.zero?
        # uii.info(I18n.t('vagrant_zones.sshport')) if config.debug
        sshport
      end

      # This filters the firmware
      def firmware(uii)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.firmware')) if config.debug
        ft = case config.firmware_type
             when /compatability/
               'BHYVE_RELEASE_CSM'
             when /UEFI/
               'BHYVE_RELEASE'
             when /BIOS/
               'BHYVE_CSM'
             when /BHYVE_DEBUG/
               'UEFI_DEBUG'
             when /BHYVE_RELEASE_CSM/
               'BIOS_DEBUG'
             end
        ft.to_s
      end

      # This filters the rdpport
      def rdpport(uii)
        config = @machine.provider_config
        uii.info(I18n.t('vagrant_zones.rdpport')) if config.debug
        config.rdpport.to_s unless config.rdpport.to_s.nil?
      end

      # This filters the vagrantuserpass
      def vagrantuserpass(machine)
        config = machine.provider_config
        # uii.info(I18n.t('vagrant_zones.vagrantuserpass')) if config.debug
        config.vagrant_user_pass unless config.vagrant_user_pass.to_s.nil?
      end

      ## List ZFS Snapshots, helper function to sort and display
      def zfssnaplistdisp(zfs_snapshots, uii, index, disk)
        uii.info("\n Disk Number: #{index}\n Disk Path: #{disk}")
        zfssnapshots = zfs_snapshots.split(/\n/).reverse
        zfssnapshots << "Snapshot\t\t\t\tUsed\tAvailable\tRefer\tPath"
        pml, rml, aml, uml, sml = 0
        zfssnapshots.reverse.each do |snapshot|
          ar = snapshot.gsub(/\s+/m, ' ').strip.split
          sml = ar[0].length.to_i if ar[0].length.to_i > sml.to_i
          uml = ar[1].length.to_i if ar[1].length.to_i > uml.to_i
          aml = ar[2].length.to_i if ar[2].length.to_i > aml.to_i
          rml = ar[3].length.to_i if ar[3].length.to_i > rml.to_i
          pml = ar[4].length.to_i if ar[4].length.to_i > pml.to_i
        end
        zfssnapshots.reverse.each_with_index do |snapshot, si|
          ar = snapshot.gsub(/\s+/m, ' ').strip.split
          strg1 = "%<sym>5s %<s>-#{sml}s %<u>-#{uml}s %<a>-#{aml}s %<r>-#{rml}s %<p>-#{pml}s"
          strg2 = "%<si>5s %<s>-#{sml}s %<u>-#{uml}s %<a>-#{aml}s %<r>-#{rml}s %<p>-#{pml}s"
          if si.zero?
            puts format strg1.to_s, sym: '#', s: ar[0], u: ar[1], a: ar[2], r: ar[3], p: ar[4]
          else
            puts format strg2.to_s, si: si - 2, s: ar[0], u: ar[1], a: ar[2], r: ar[3], p: ar[4]
          end
        end
      end

      ## List ZFS Snapshots
      def zfssnaplist(datasets, opts, uii)
        # config = @machine.provider_config
        # name = @machine.name
        uii.info(I18n.t('vagrant_zones.zfs_snapshot_list'))
        datasets.each_with_index do |disk, index|
          zfs_snapshots = execute(false, "#{@pfexec} zfs list -t snapshot | grep #{disk} || true")
          next if zfs_snapshots.nil?

          ds = opts[:dataset].scan(/\D/).empty? unless opts[:dataset].nil?
          if ds
            next if opts[:dataset].to_i != index
          else
            next unless opts[:dataset] == disk || opts[:dataset].nil? || opts[:dataset] == 'all'
          end
          zfssnaplistdisp(zfs_snapshots, uii, index, disk)
        end
      end

      ## Create ZFS Snapshots
      def zfssnapcreate(datasets, opts, uii)
        uii.info(I18n.t('vagrant_zones.zfs_snapshot_create'))
        if opts[:dataset] == 'all'
          datasets.each do |disk|
            uii.info("  - #{disk}@#{opts[:snapshot_name]}")
            execute(false, "#{@pfexec} zfs snapshot #{disk}@#{opts[:snapshot_name]}")
          end
        else
          ds = opts[:dataset].scan(/\D/).empty? unless opts[:dataset].nil?
          if ds
            datasets.each_with_index do |disk, index|
              next unless opts[:dataset].to_i == index.to_i

              execute(false, "#{@pfexec} zfs snapshot #{disk}@#{opts[:snapshot_name]}")
              uii.info("  - #{disk}@#{opts[:snapshot_name]}")
            end
          else
            execute(false, "#{@pfexec} zfs snapshot #{opts[:dataset]}@#{opts[:snapshot_name]}") if datasets.include?(opts[:dataset])
            uii.info("  - #{opts[:dataset]}@#{opts[:snapshot_name]}") if datasets.include?(opts[:dataset])
          end
        end
      end

      ## Destroy ZFS Snapshots
      def zfssnapdestroy(datasets, opts, uii)
        uii.info(I18n.t('vagrant_zones.zfs_snapshot_destroy'))
        if opts[:dataset].to_s == 'all'
          datasets.each do |disk|
            output = execute(false, "#{@pfexec} zfs list -t snapshot -o name | grep #{disk}")
            ## Never delete the source when doing all
            output = output.split(/\n/).drop(1)
            ## Delete in Reverse order
            output.reverse.each do |snaps|
              cmd = "#{@pfexec} zfs destroy #{snaps}"
              execute(false, cmd)
              uii.info("  - #{snaps}")
            end
          end
        else
          ## Specify the dataset by number
          datasets.each_with_index do |disk, dindex|
            next unless dindex.to_i == opts[:dataset].to_i

            output = execute(false, "#{@pfexec} zfs list -t snapshot -o name | grep #{disk}")
            output = output.split(/\n/).drop(1)
            output.each_with_index do |snaps, spindex|
              if opts[:snapshot_name].to_i == spindex && opts[:snapshot_name].to_s != 'all'
                uii.info("  - #{snaps}")
                execute(false, "#{@pfexec} zfs destroy #{snaps}")
              end
              if opts[:snapshot_name].to_s == 'all'
                uii.info("  - #{snaps}")
                execute(false, "#{@pfexec} zfs destroy #{snaps}")
              end
            end
          end
          ## Specify the Dataset by path
          cmd = "#{@pfexec} zfs destroy #{opts[:dataset]}@#{opts[:snapshot_name]}"
          execute(false, cmd) if datasets.include?("#{opts[:dataset]}@#{opts[:snapshot_name]}")
        end
      end

      ## This will list Cron Jobs for Snapshots to take place
      def zfssnapcronlist(uii, disk, opts, cronjobs)
        return unless opts[:dataset].to_s == disk.to_s || opts[:dataset].to_s == 'all'

        # config = @machine.provider_config
        # name = @machine.name
        uii.info(I18n.t('vagrant_zones.cron_entries'))
        h = { h: 'hourly', d: 'daily', w: 'weekly', m: 'monthly' }
        h.each do |_k, d|
          next unless opts[:list] == d || opts[:list] == 'all'

          uii.info(cronjobs[d.to_sym]) unless cronjobs[d.to_sym].nil?
        end
      end

      ## This will delete Cron Jobs for Snapshots to take place
      def zfssnapcrondelete(uii, disk, opts, cronjobs)
        return unless opts[:dataset].to_s == disk.to_s || opts[:dataset].to_s == 'all'

        sc = "#{@pfexec} crontab"
        rmcr = "#{sc} -l | grep -v "
        h = { h: 'hourly', d: 'daily', w: 'weekly', m: 'monthly' }
        uii.info(I18n.t('vagrant_zones.cron_delete'))
        h.each do |_k, d|
          next unless opts[:delete] == d || opts[:delete] == 'all'

          cj = cronjobs[d.to_sym].to_s.gsub(/\*/, '\*')
          rc = "#{rmcr}'#{cj}' | #{sc}"
          uii.info("  - Removing Cron: #{cj}") unless cronjobs[d.to_sym].nil?
          execute(false, rc) unless cronjobs[d.to_sym].nil?
        end
      end

      ## This will set Cron Jobs for Snapshots to take place
      def zfssnapcronset(uii, disk, opts, cronjobs)
        return unless opts[:dataset].to_s == disk.to_s || opts[:dataset].to_s == 'all'

        config = @machine.provider_config
        name = @machine.name
        uii.info(I18n.t('vagrant_zones.cron_set'))
        snpshtr = config.snapshot_script.to_s
        shrtcr = "( #{@pfexec} crontab -l; echo "
        h = {}
        sf = { freq: opts[:set_frequency], rtn: opts[:set_frequency_rtn] }
        rtn = { h: 24, d: 8, w: 5, m: 1 }
        ct = { h: '0 1-23 * * * ', d: '0 0 * * 0-5 ', w: '0 0 * * 6 ', m: '0 0 1 * * ' }
        h[:hourly] = { rtn: rtn[:h], ct: ct[:h] }
        h[:daily] = { rtn: rtn[:d], ct: ct[:d] }
        h[:weekly] = { rtn: rtn[:w], ct: ct[:w] }
        h[:monthly] = { rtn: rtn[:m], ct: ct[:m] }
        h.each do |k, d|
          next unless (k.to_s == sf[:freq] || sf[:freq] == 'all') && cronjobs[k].nil?

          cj = "#{d[:ct]}#{snpshtr} -p #{k} -r -n #{sf[:rtn]} #{disk} # #{name}" unless sf[:rtn].nil?
          cj = "#{d[:ct]}#{snpshtr} -p #{k} -r -n #{d[:rtn]} #{disk} # #{name}" if sf[:rtn].nil?
          h[k] = { rtn: rtn[:h], ct: ct[:h], cj: cj }
          setcron = "#{shrtcr}'#{cj}' ) | #{@pfexec} crontab"
          uii.info("Setting Cron: #{setcron}")
          execute(false, setcron)
        end
      end

      ## Configure ZFS Snapshots Crons
      def zfssnapcron(datasets, opts, uii)
        name = @machine.name
        # config = @machine.provider_config
        crons = execute(false, "#{@pfexec} crontab -l").split("\n")
        rtnregex = '-p (weekly|monthly|daily|hourly)'
        opts[:dataset] = 'all' if opts[:dataset].nil?
        datasets.each do |disk|
          cronjobs = {}
          crons.each do |tasks|
            next if tasks.empty? || tasks[/^#/]

            case tasks[/#{rtnregex}/, 1]
            when 'hourly'
              hourly = tasks if tasks[/# #{name}/] && tasks[/#{disk}/]
              cronjobs.merge!(hourly: hourly) if tasks[/# #{name}/] && tasks[/#{disk}/]
            when 'daily'
              daily = tasks if tasks[/# #{name}/] && tasks[/#{disk}/]
              cronjobs.merge!(daily: daily) if tasks[/# #{name}/] && tasks[/#{disk}/]
            when 'weekly'
              weekly = tasks if tasks[/# #{name}/] && tasks[/#{disk}/]
              cronjobs.merge!(weekly: weekly) if tasks[/# #{name}/] && tasks[/#{disk}/]
            when 'monthly'
              monthly = tasks if tasks[/# #{name}/] && tasks[/#{disk}/]
              cronjobs.merge!(monthly: monthly) if tasks[/# #{name}/] && tasks[/#{disk}/]
            end
          end
          zfssnapcronlist(uii, disk, opts, cronjobs) unless opts[:list].nil?
          zfssnapcrondelete(uii, disk, opts, cronjobs) unless opts[:delete].nil?
          zfssnapcronset(uii, disk, opts, cronjobs) unless opts[:set_frequency].nil?
        end
      end

      # This helps us manage ZFS Snapshots
      def zfs(uii, job, opts)
        name = @machine.name
        config = @machine.provider_config
        bootconfigs = config.boot
        datasetroot = "#{bootconfigs['array']}/#{bootconfigs['dataset']}/#{name}/#{bootconfigs['volume_name']}"
        datasets = []
        datasets << datasetroot.to_s
        config.additional_disks&.each do |disk|
          additionaldataset = "#{disk['array']}/#{disk['dataset']}/#{name}/#{disk['volume_name']}"
          datasets << additionaldataset.to_s
        end
        case job
        when 'list'
          zfssnaplist(datasets, opts, uii)
        when 'create'
          zfssnapcreate(datasets, opts, uii)
        when 'destroy'
          zfssnapdestroy(datasets, opts, uii)
        when 'cron'
          zfssnapcron(datasets, opts, uii)
        end
      end

      # Halts the Zone, first via shutdown command, then a halt.
      def halt(uii)
        name = @machine.name
        config = @machine.provider_config

        ## Check state in zoneadm
        vm_state = execute(false, "#{@pfexec} zoneadm -z #{name} list -p | awk -F: '{ print $3 }'")
        uii.info(I18n.t('vagrant_zones.graceful_shutdown'))
        begin
          Timeout.timeout(config.clean_shutdown_time) do
            execute(false, "#{@pfexec} zoneadm -z #{name} shutdown") if vm_state == 'running'
          end
        rescue Timeout::Error
          uii.info(I18n.t('vagrant_zones.graceful_shutdown_failed') + config.clean_shutdown_time.to_s)
          begin
            Timeout.timeout(config.clean_shutdown_time) do
              execute(false, "#{@pfexec} zoneadm -z #{name} halt")
            end
          rescue Timeout::Error
            raise Errors::TimeoutHalt
          end
        end
      end

      # Destroys the Zone configurations and path
      def destroy(id)
        name = @machine.name
        id.info(I18n.t('vagrant_zones.leaving'))
        id.info(I18n.t('vagrant_zones.destroy_zone'))
        vm_state = execute(false, "#{@pfexec} zoneadm -z #{name} list -p | awk -F: '{ print $3 }'")

        ## If state is installed, uninstall from zoneadm and destroy from zonecfg
        if vm_state == 'installed'
          id.info(I18n.t('vagrant_zones.bhyve_zone_config_uninstall'))
          execute(false, "#{@pfexec} zoneadm -z #{name} uninstall -F")
          id.info(I18n.t('vagrant_zones.bhyve_zone_config_remove'))
          execute(false, "#{@pfexec} zonecfg -z #{name} delete -F")
        end

        ## If state is configured or incomplete, uninstall from destroy from zonecfg
        if %w[incomplete configured].include?(vm_state)
          id.info(I18n.t('vagrant_zones.bhyve_zone_config_remove'))
          execute(false, "#{@pfexec} zonecfg -z #{name} delete -F")
        end

        ### Nic Configurations
        state = 'delete'
        id.info(I18n.t('vagrant_zones.networking_int_remove'))
        network(id, state)
      end
    end
  end
end
