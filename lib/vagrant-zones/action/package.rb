# frozen_string_literal: true

require 'log4r'
module VagrantPlugins
  module ProviderZone
    module Action
      # This is used to package the VM into a box
      class Package
        def initialize(app, env)
          @logger = Log4r::Logger.new('vagrant_zones::action::import')
          @app = app
          @executor = Executor::Exec.new
          @pfexec = if Process.uid.zero?
                      ''
                    elsif system('sudo -v')
                      'sudo'
                    else
                      'pfexec'
                    end
          env['package.output'] ||= 'package.box'
        end

        def execute(*cmd, **opts, &block)
          @executor.execute(*cmd, **opts, &block)
        end

        def call(env)
          @machine = env[:machine]
          @driver = @machine.provider.driver
          name = @machine.name
          boxname = env['package.output']
          brand = @machine.provider_config.brand
          kernel = @machine.provider_config.kernel
          vcc = @machine.provider_config.vagrant_cloud_creator
          boxshortname = @machine.provider_config.boxshortname
          raise "#{boxname}: Already exists" if File.exist?(boxname)

          ## Create Snapshot
          tmp_dir = "#{Dir.pwd}/_tmp_package"
          Dir.mkdir(tmp_dir)
          datasetpath = "#{@machine.provider_config.boot['array']}/#{@machine.provider_config.boot['dataset']}/#{name}"
          t = Time.new
          d = '-'
          c = ':'
          datetime = %(#{t.year}#{d}#{t.month}#{d}#{t.day}#{d}#{t.hour}#{c}#{t.min}#{c}#{t.sec})
          snapshot_create(datasetpath, datetime, env[:ui], @machine.provider_config)
          snapshot_send(datasetpath, "#{tmp_dir}/box.zss", datetime, env[:ui], @machine.provider_config)
          ## snapshot_delete(datasetpath, env[:ui], datetime)

          # Package VM
          extra = ''

          ## Include User Extra Files
          @tmp_include = "#{tmp_dir}/_include"
          if env['package.include']
            extra = './_include'
            Dir.mkdir(@tmp_include)
            env['package.include'].each do |f|
              env[:ui].info("Including user file: #{f}")
              FileUtils.cp(f, @tmp_include)
            end
          end

          ## Include Vagrant file
          if env['package.vagrantfile']
            extra = './_include'
            Dir.mkdir(@tmp_include) unless File.directory?(@tmp_include)
            env[:ui].info('Including user Vagrantfile')
            FileUtils.cp(env['package.vagrantfile'], "#{@tmp_include}/Vagrantfile")
          end

          ## Create the Metadata and Vagrantfile
          Dir.chdir(tmp_dir)
          File.write('./metadata.json', metadata_content(brand, kernel, vcc, boxshortname))
          File.write('./Vagrantfile', vagrantfile_content(brand, kernel, datasetpath))

          ## Create the Box file
          assemble_box(boxname, extra)
          FileUtils.mv("#{tmp_dir}/#{boxname}", "../#{boxname}")
          Dir.chdir('../')
          FileUtils.rm_rf(tmp_dir)

          env[:ui].info("Box created, You can now add the box: 'vagrant box add #{boxname} --nameofnewbox'")
          @app.call(env)
        end

        def snapshot_create(datasetpath, datetime, uii, config)
          uii.info('Creating a Snapshot of the box.')
          result = execute(true, "#{@pfexec} zfs snapshot -r #{datasetpath}/boot@vagrant_box#{datetime}")
          uii.info("#{@pfexec} zfs snapshot -r #{datasetpath}/boot@vagrant_box#{datetime}") if result.zero? && config.debug
        end

        def snapshot_delete(datasetpath, uii, datetime)
          result = execute(true, "#{@pfexec} zfs destroy -r -f #{datasetpath}/boot@vagrant_box#{datetime}")
          uii.info("#{@pfexec} zfs destroy -r -f #{datasetpath}/boot@vagrant_box#{datetime}") if result.zero? && config.debug
        end

        def snapshot_send(datasetpath, destination, datetime, uii, config)
          uii.info('Sending Snapshot to ZFS Send Stream image.')
          result = execute(true, "#{@pfexec} zfs send #{datasetpath}/boot@vagrant_box#{datetime} > #{destination}")
          puts "#{@pfexec} zfs send -r #{datasetpath}/boot@vagrant_box#{datetime} > #{destination}" if result.zero? && config.debug
        end

        def metadata_content(brand, _kernel, vcc, boxshortname)
          <<-ZONEBOX
          {
            "provider": "zone",
            "format": "zss",
            "brand": "#{brand}",
            "url": "https://app.vagrantup.com/#{vcc}/boxes/#{boxshortname}"
          }
          ZONEBOX
        end

        def vagrantfile_content(brand, _kernel, datasetpath)
          <<-ZONEBOX
          Vagrant.configure('2') do |config|
            config.vm.provider :zone do |zone|
              zone.brand = "#{brand}"
              zone.datasetpath = "#{datasetpath}"
            end
          end
          user_vagrantfile = File.expand_path('../_include/Vagrantfile', __FILE__)
          load user_vagrantfile if File.exists?(user_vagrantfile)
          ZONEBOX
        end

        def assemble_box(boxname, extra)
            `"tar -cvzf #{boxname} ./metadata.json ./Vagrantfile ./box.zss #{extra}` if system('uname -a | grep Linux')
            `"tar -cvzEf #{boxname} ./metadata.json ./Vagrantfile ./box.zss #{extra}` unless system('uname -a | grep Linux')
        end
      end
    end
  end
end
