# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'log4r'
require 'vagrant/util/safe_chdir'
require 'vagrant/util/subprocess'
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
          include_files = {}
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
          if env['package.include']
            env['package.include'].each do |file|
              source = Pathname.new(file)
              dest = if source.relative?
                       source
                     else
                       source.basename
                     end

              files[file] = dest
            end

            if env['package.vagrantfile']
              # Vagrantfiles are treated special and mapped to a specific file
              files[env['package.vagrantfile']] = '_Vagrantfile'
            end

            # Verify the mapping
            files.each_key do |from|
              raise Vagrant::Errors::PackageIncludeMissing, file: from unless File.exist?(from)
            end

            # Save the mapping
            include_files = files
          end

          copy_include_files(include_files, tmp_dir, env[:ui])

          ## Create the Metadata and Vagrantfile
          Dir.chdir(tmp_dir)

          metadata_content_hash = {
            'provider' => 'zone',
            'architecture' => 'amd64',
            'brand' => brand,
            'format' => 'zss',
            'kernel' => kernel,
            'url' => 'https://app.vagrantup.com/#{vcc}/boxes/#{boxshortname}'
           }

          File.write('./metadata.json', metadata_content_hash)

          user_vagrantfile = File.expand_path('Vagrantfile', __dir__)
          vagrantfile_content = %{require 'yaml'
          require File.expand_path("#{File.dirname(__FILE__)}/Hosts.rb")
          settings = YAML::load(File.read("#{File.dirname(__FILE__)}/Hosts.yml"))
          Vagrant.configure("2") do |config|
            Hosts.configure(config, settings)
          end}
          vagrantfile_content = File.read(user_vagrantfile ) if File.exist?(user_vagrantfile)
          File.write('./Vagrantfile', vagrantfile_content)

          ## Create the Box file
          assemble_box(boxname)
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

        # This method copies the include files (passed in via command line) to the
        # temporary directory so they are included in a sub-folder within the actual box
        def copy_include_files(include_files, destination, uii)
          include_files.each do |from, dest|
            include_directory = Pathname.new(destination)
            to = include_directory.join(dest)
            FileUtils.mkdir_p(to.parent)
            if File.directory?(from)
              FileUtils.cp_r(Dir.glob(from), to.parent, preserve: true)
            else
              FileUtils.cp(from, to, preserve: true)
            end
          end
        end

        def assemble_box(boxname)
          is_linux = `bash -c '[[ "$(uname -a)" =~ "Linux" ]]'`
          files = Dir.glob(File.join('.', '*'))
          `tar -cvzf ../#{boxname} #{files.join(' ')}` if is_linux
          `tar -cvzEf ../#{boxname} #{files.join(' ')}` unless is_linux
        end
      end
    end
  end
end
