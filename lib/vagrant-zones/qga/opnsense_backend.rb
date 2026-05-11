# frozen_string_literal: true

module VagrantPlugins
  module ProviderZone
    module QGA
      # OPNsense detection only for v1; full integration via configctl + config.xml XPath is TODO.
      # TODO(opnsense): implement configctl + /conf/config.xml XPath editing,
      #                 then run `configctl interface reconfigure all`.
      class OpnsenseBackend < BaseBackend
        OPNSENSE_VERSION_DIR = '/usr/local/opnsense/version'

        def detect?(qga)
          qga.exec('/usr/bin/test', args: ['-d', OPNSENSE_VERSION_DIR], timeout: 10)[:exitcode].zero?
        rescue StandardError
          false
        end

        def apply(*)
          raise Errors::QGABackendNotImplemented, backend: 'opnsense',
                                                  details: 'OPNsense network configuration via configctl + config.xml is not yet implemented in vagrant-zones. Track in repository issues.'
        end
      end
    end
  end
end
