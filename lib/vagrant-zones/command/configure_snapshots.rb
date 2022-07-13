# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module Command
      # This is used to configure snapshots for the zone
      class ConfigureSnapshots < Vagrant.plugin('2', :command)
        def execute
          options = {}
          opts = OptionParser.new do |o|
            o.banner = 'Usage: vagrant zone zfssnapshot list [options]'
            o.on('--dataset DATASETPATH/ALL', 'Specify path to enable snapshots on, defaults to ALL') do |p|
              options[:dataset] = p
            end
            frequencymsg = 'Set a policy with one of the available optional frequencies'
            o.on('--set_frequency <hourly/daily/weekly/monthly/all>', frequencymsg) do |p|
              options[:set_frequency] = p
            end
            frequency_rtnmsg = 'Number of snapshots to take for the frequency policy'
            o.on('--set_frequency_rtn <#>/defaults ', frequency_rtnmsg) do |p|
              options[:set_frequency_rtn] = p
            end
            deletemsg = 'Delete frequency policy'
            o.on('--delete  <hourly/daily/weekly/monthly/all>', deletemsg) do |p|
              options[:delete] = p
            end
            listmsg = 'Show Cron Policies'
            o.on('--list  <hourly/daily/weekly/monthly/all>', listmsg) do |p|
              options[:list] = p
            end
          end

          argv = parse_options(opts)
          return unless argv

          unless argv.length <= 4
            @env.ui.info(opts.help)
            return
          end

          with_target_vms(argv, provider: :zone) do |machine|
            driver = machine.provider.driver
            driver.zfs(@env.ui, 'cron', options)
          end
        end
      end
    end
  end
end
