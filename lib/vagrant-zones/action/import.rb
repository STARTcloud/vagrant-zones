# frozen_string_literal: true

require 'net/http'
require 'vagrant-zones/util/subprocess'
require 'vagrant/box_metadata'
require 'vagrant/util/downloader'
require 'vagrant/util/platform'
require 'vagrant/util/safe_chdir'
require 'vagrant/util/subprocess'

module VagrantPlugins
  module ProviderZone
    module Action
      # This will import the zone boot image from the cloud, cache or file
      class Import
        def initialize(app, _env)
          @logger = Log4r::Logger.new('vagrant_zones::action::import')
          @joyent_images_url = 'https://images.joyent.com/images/'
          @app = app
        end

        def validate_uuid_format(uuid)
          uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
          return true if uuid_regex.match?(uuid.to_s.downcase)
        end

        def call(env)
          @machine = env[:machine]
          @executor = Executor::Exec.new
          image = @machine.config.vm.box
          curdir = Dir.pwd
          datadir = @machine.data_dir
          @driver = @machine.provider.driver
          ui = env[:ui]
          ui.info(I18n.t('vagrant_zones.meeting'))
          ui.info(I18n.t('vagrant_zones.datadir'))
          ui.info("  #{datadir}")
          ui.info(I18n.t('vagrant_zones.detecting_box'))

          # If image ends on '.zss' it's a local ZFS snapshot which should be used
          if image[-4, 4] == '.zss'
            if File.exist?("#{curdir}/#{image}")
              FileUtils.cp("#{curdir}/#{image}", "#{datadir}/#{image}")
              ui.info(I18n.t('vagrant_zones.zfs_snapshot_stream_detected'))
            elsif !File.exist?("#{datadir}/#{image}")
              raise Vagrant::Errors::BoxNotFound
            end
          ## If image looks like an UUID, download the ZFS snapshot from Joyent images server
          elsif validate_uuid_format(image)
            raise Vagrant::Errors::BoxNotFound unless check(image, ui)

            uri = URI("#{@joyent_images_url}#{image}/file")
            Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
              request = Net::HTTP::Get.new uri
              http.request request do |response|
                file_size = response['content-length'].to_i
                amount_downloaded = 0
                ratelimit = 0
                rate = 500
                large_file = "#{datadir}/#{image}"
                File.open(large_file, 'wb') do |io|
                  response.read_body do |chunk|
                    io.write chunk
                    amount_downloaded += chunk.size
                    ui.rewriting do |uiprogress|
                      ratelimit += 1
                      if ratelimit >= rate
                        uiprogress.clear_line
                        status = format('%.2f%%', (amount_downloaded.to_f / file_size * 100))
                        uiprogress.info(I18n.t('vagrant_zones.importing_joyent_image') + "#{image} ==> ", new_line: false)
                        uiprogress.report_progress(status, 100, false)
                        ratelimit = 0
                      end
                    end
                  end
                  ui.clear_line
                end
              end
            end
            ui.info(I18n.t('vagrant_zones.joyent_image_uuid_detected') + image)

          ## If it's a regular name (everything else), try to find it on Vagrant Cloud
          else
            # Support zss maybe zst? Same thing? format only for now, use other images and convert later
            box_format = env[:machine].box.metadata['format'] unless env[:machine].box.nil?

            if box_format == 'ovf'
              ## Insert Future Code to try to convert existing box
              ui.info(I18n.t('vagrant_zones.detected_ovf_format'))
            end

            ## No Local box template exists, Lets use Vagrant HandleBox to download the Box template
            ui.info(I18n.t('vagrant_zones.vagrant_cloud_box_detected'))
            ui.info("  #{image}")
            ui.clear_line
          end
          @app.call(env)
        end

        def execute(*cmd, **opts, &block)
          @executor.execute(*cmd, **opts, &block)
        end

        def check(uuid, env_ui)
          execute(true, "curl --output /dev/null --silent  -r 0-0 --fail #{@joyent_images_url}/#{uuid}")
          env_ui.info(I18n.t('vagrant_zones.joyent_image_uuid_verified') + @joyent_images_url + uuid)
        end
      end
    end
  end
end
