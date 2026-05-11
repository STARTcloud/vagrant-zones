# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # pfSense detection only for v1; full integration via pfSsh.php playback is TODO.
      # TODO(pfsense): implement pfSsh.php playback to apply interface settings
      #                and reload via filter/interfaces reload.
      class PfsenseBackend < BaseBackend
        def detect?(qga)
          qga.exec('/bin/sh', args: ['-c', 'grep -q pfSense /etc/version 2>/dev/null'], timeout: 10)[:exitcode].zero?
        rescue StandardError
          false
        end

        def apply(*)
          raise Errors::QGABackendNotImplemented, backend: 'pfsense',
                                                  details: 'pfSense network configuration via pfSsh.php is not yet implemented in vagrant-zones. Track in repository issues.'
        end
      end
    end
  end
end
