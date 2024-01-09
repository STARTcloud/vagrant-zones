# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'log4r'
require 'json'
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
          mpc = @machine.provider_config
          brand = mpc.brand
          kernel = mpc.kernel
          vcc = mpc.vagrant_cloud_creator
          boot = mpc.boot
          boxshortname = mpc.boxshortname
          files = {}
          raise "#{boxname}: Already exists" if File.exist?(boxname)

          ## Create Snapshot
          FileUtils.mkdir_p("#{Dir.pwd}/_tmp_package")
          datasetpath = "#{mpc.boot['array']}/#{mpc.boot['dataset']}/#{name}"
          datetime = Time.new.strftime('%Y-%m-%d-%H:%M:%S')
          snapshot_create(datasetpath, datetime, env[:ui], mpc)
          snapshot_send(datasetpath, "#{Dir.pwd}/_tmp_package/box.zss", datetime, env[:ui], mpc)

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
            include_directory = Pathname.new("#{Dir.pwd}/_tmp_package/")
            to = include_directory.join(dest)
            FileUtils.mkdir_p(to.parent)
            if File.directory?(from)
              FileUtils.cp_r(Dir.glob(from), to.parent, preserve: true)
            else
              FileUtils.cp(from, to, preserve: true)
            end
          end

          ## Create a Vagrantfile or load from Users Defined File
          vagrantfile_content = <<~'CODE'
            require 'yaml'
            require_relative 'Hosts'
            settings = YAML::load(File.read("#{File.dirname(__FILE__)}/Hosts.yml"))
            Vagrant.configure("2") do |config|
              Hosts.configure(config, settings)
            end
          CODE
          File.write("#{Dir.pwd}/_tmp_package/Vagrantfile", vagrantfile_content)

          files[env['package.vagrantfile']] = '_Vagrantfile' if env['package.vagrantfile']

          info_content_hash = {
            'boxname' => "#{boxshortname}",
            'Author' => "#{vcc}",
            'Vagrant-Zones' => "This box was built with Vagrant-Zones: https://github.com/STARTcloud/vagrant-zones"
          }
          File.write("#{Dir.pwd}/_tmp_package/info.json", info_content_hash.to_json)

          metadata_content_hash = {
            'provider' => 'zone',
            'architecture' => 'amd64',
            'brand' => brand,
            'format' => 'zss',
            'url' => "https://app.vagrantup.com/#{vcc}/boxes/#{boxshortname}"
          }

          metadata_content_hash['kernel'] = kernel if !kernel.nil? && kernel != false
          File.write("#{Dir.pwd}/_tmp_package/metadata.json", metadata_content_hash.to_json)

          ## Create the Box file
          assemble_box(boxname, "#{Dir.pwd}/_tmp_package")
          FileUtils.rm_rf("#{Dir.pwd}/_tmp_package")

          env[:ui].info("Box created, You can now add the box: 'vagrant box add #{boxname} --name newbox'")
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
          uii.info("#{@pfexec} zfs send -r #{datasetpath}/boot@vagrant_box#{datetime} > #{destination}") if result.zero? && config.debug
        end

        def assemble_box(boxname, tmp_dir)
          is_linux = `bash -c '[[ "$(uname -a)" =~ "Linux" ]]'`
          Dir.chdir(tmp_dir) do
          files = Dir.glob(File.join('.', '*'))
          tar_command = is_linux ? "tar -cvzf ../#{boxname}" : "tar -cvzEf ../#{boxname}"
          `#{tar_command} #{files.join(' ')}`
          end
        end
      end
    end
  end
end
