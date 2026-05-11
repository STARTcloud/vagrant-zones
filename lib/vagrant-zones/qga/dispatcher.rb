# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # Picks the right backend for the guest OS and orchestrates apply + verify
      # with a fall-through chain for Linux variants.
      class Dispatcher
        # Order matters: Linux chain is tried sequentially; first to apply+verify wins.
        LINUX_CHAIN = [
          QGA::NetplanBackend,
          QGA::NetworkManagerBackend,
          QGA::SystemdNetworkdBackend,
          QGA::IfupdownBackend
        ].freeze

        def initialize(qga, config)
          @qga = qga
          @config = config
        end

        def dispatch(uii, nics)
          if @config.qga_network_script && !@config.qga_network_script.to_s.empty?
            run_user_script(uii, nics)
            return
          end

          os = @qga.osinfo
          uii.info("#{I18n.t('vagrant_zones.qga_osinfo_detected')} #{os['id']} (#{os['pretty-name']})")
          case os_family(os)
          when :windows  then run_single(uii, QGA::WindowsBackend.new, nics)
          when :illumos  then run_single(uii, QGA::IllumosBackend.new, nics)
          when :pfsense  then run_single(uii, QGA::PfsenseBackend.new, nics)
          when :opnsense then run_single(uii, QGA::OpnsenseBackend.new, nics)
          when :freebsd  then run_single(uii, QGA::FreebsdBackend.new, nics)
          when :linux    then run_chain(uii, nics)
          else
            raise Errors::QGABackendNotImplemented, backend: os['id'].to_s,
                                                    details: "no qga backend registered for guest OS #{os.inspect}"
          end
        end

        private

        def os_family(os)
          id = os['id'].to_s.downcase
          return :windows if id == 'mswindows' || id.include?('windows')
          return :illumos if %w[omnios sunos illumos smartos].any? { |k| id.include?(k) } || os['kernel-version'].to_s =~ /illumos|SunOS/i
          return freebsd_family if id == 'freebsd'
          return :linux if id == 'gnu/linux' || id.include?('linux') || os['kernel-release'].to_s =~ /linux/i

          :unknown
        end

        def freebsd_family
          return :pfsense  if QGA::PfsenseBackend.new.detect?(@qga)
          return :opnsense if QGA::OpnsenseBackend.new.detect?(@qga)

          :freebsd
        end

        def run_user_script(uii, nics)
          backend = QGA::UserScriptBackend.new(@config.qga_network_script)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_selected')} user-script (#{@config.qga_network_script})")
          backend.apply(uii, @qga, nics, {})
          uii.info("#{I18n.t('vagrant_zones.qga_backend_applied')} user-script")
        end

        def run_single(uii, backend, nics)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_selected')} #{backend.name}")
          backend.apply(uii, @qga, nics, {})
          unless backend.verify(@qga, nics)
            uii.info("#{I18n.t('vagrant_zones.qga_backend_verify_failed')} #{backend.name}")
            backend.cleanup(uii, @qga, nics)
            raise Errors::QGAAllBackendsFailed, attempted: backend.name
          end
          uii.info("#{I18n.t('vagrant_zones.qga_backend_applied')} #{backend.name}")
        end

        def run_chain(uii, nics)
          attempted = []
          last_error = nil
          winning = LINUX_CHAIN.find do |klass|
            backend = klass.new
            next false unless safe_detect(backend)

            try_backend?(uii, backend, nics, attempted) do |err|
              last_error = err
            end
          end
          return if winning

          raise Errors::QGAAllBackendsFailed, attempted: format_attempted(attempted, last_error)
        end

        def try_backend?(uii, backend, nics, attempted)
          uii.info("#{I18n.t('vagrant_zones.qga_backend_selected')} #{backend.name}")
          attempted << backend.name
          begin
            backend.apply(uii, @qga, nics, {})
            if backend.verify(@qga, nics)
              uii.info("#{I18n.t('vagrant_zones.qga_backend_applied')} #{backend.name}")
              return true
            end
            uii.info("#{I18n.t('vagrant_zones.qga_backend_verify_failed')} #{backend.name}")
          rescue Errors::QGAError => e
            yield e.message
            uii.info("#{backend.name} apply error: #{e.message}")
          end
          backend.cleanup(uii, @qga, nics)
          false
        end

        def format_attempted(attempted, last_error)
          return '(none detected)' if attempted.empty?

          base = attempted.join(', ')
          last_error ? "#{base}; last error: #{last_error}" : base
        end

        def safe_detect(backend)
          backend.detect?(@qga)
        rescue StandardError
          false
        end
      end
    end
  end
end
