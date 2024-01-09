# frozen_string_literal: true

require 'fileutils'
require 'pathname'
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

        def execute(...)
          @executor.execute(...)
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
          files = {}
          raise "#{boxname}: Already exists" if File.exist?(boxname)

          ## Create Snapshot
          tmp_dir = "#{Dir.pwd}/_tmp_package"
          Dir.mkdir(tmp_dir)
          datasetpath = "#{@machine.provider_config.boot['array']}/#{@machine.provider_config.boot['dataset']}/#{name}"
          t = Time.new
          datetime = %(#{t.year}-#{t.month}-#{t.day}-#{t.hour}:#{t.min}:#{t.sec})
          snapshot_create(datasetpath, datetime, env[:ui], @machine.provider_config)
          snapshot_send(datasetpath, "#{tmp_dir}/box.zss", datetime, env[:ui], @machine.provider_config)

          ## Include User Extra Files
          env['package.include'].each do |file|
            source = Pathname.new(file)
            dest = if source.relative?
                     source
                   else
                     source.basename
                   end
            files[file] = dest
          end

          # Verify the mapping
          files.each_key do |from|
            raise Vagrant::Errors::PackageIncludeMissing, file: from unless File.exist?(from)
          end

          files.each do |from, dest|
            include_directory = Pathname.new(tmp_dir)
            to = include_directory.join(dest)
            FileUtils.mkdir_p(to.parent)
            if File.directory?(from)
              FileUtils.cp_r(Dir.glob(from), to.parent, preserve: true)
            else
              FileUtils.cp(from, to, preserve: true)
            end
          end

          ## Create a Vagrantfile or load from Users Defined File
          vagrantfile_content = %{require 'yaml'
require File.expand_path("#{File.dirname(__FILE__)}/Hosts.rb")
settings = YAML::load(File.read("#{File.dirname(__FILE__)}/Hosts.yml"))
Vagrant.configure("2") do |config|
  Hosts.configure(config, settings)
end}
          File.write("#{tmp_dir}/Vagrantfile", vagrantfile_content)

          files[env['package.vagrantfile']] = '_Vagrantfile' if env['package.vagrantfile']

          metadata_content_hash = {
            'provider' => 'zone',
            'architecture' => 'amd64',
            'brand' => brand,
            'format' => 'zss',
            'url' => "https://app.vagrantup.com/#{vcc}/boxes/#{boxshortname}"
          }
          if defined?(kernel)
            metadata_content_hash['kernel'] = kernel 
          end
          
          File.write("#{tmp_dir}/metadata.json", metadata_content_hash)

          ## Create the Box file
          assemble_box(boxname, tmp_dir)
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

        def assemble_box(boxname, tmp_dir)
          is_linux = `bash -c '[[ "$(uname -a)" =~ "Linux" ]]'`
          Dir.chdir(tmp_dir)
          files = Dir.glob(File.join('.', '*'))
          `tar -cvzf ../#{boxname} #{files.join(' ')}` if is_linux
          `tar -cvzEf ../#{boxname} #{files.join(' ')}` unless is_linux
        end
      end
    end
  end
end
