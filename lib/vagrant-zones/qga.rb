# frozen_string_literal: true

require 'pathname'

module VagrantPlugins
  module ProviderZone
    # QEMU Guest Agent subsystem: JSON-RPC client over virtio-console UNIX socket,
    # dispatcher for guest-OS detection, and per-backend network writers.
    module QGA
      # Pad each octet to 2 hex digits, lowercase. Matches qga's hardware-address output.
      def self.normalize_mac(str)
        str.to_s.split(':').map { |x| format('%02x', x.to_i(16)) }.join(':').downcase
      end

      qga_root = Pathname.new(File.expand_path('qga', __dir__))
      autoload :Client,                  qga_root.join('client')
      autoload :ClientExec,              qga_root.join('client_exec')
      autoload :Dispatcher,              qga_root.join('dispatcher')
      autoload :BaseBackend,             qga_root.join('base_backend')
      autoload :NetplanBackend,          qga_root.join('netplan_backend')
      autoload :NetworkManagerBackend,   qga_root.join('network_manager_backend')
      autoload :SystemdNetworkdBackend,  qga_root.join('systemd_networkd_backend')
      autoload :IfupdownBackend,         qga_root.join('ifupdown_backend')
      autoload :WindowsBackend,          qga_root.join('windows_backend')
      autoload :IllumosBackend,          qga_root.join('illumos_backend')
      autoload :FreebsdBackend,          qga_root.join('freebsd_backend')
      autoload :OpnsenseBackend,         qga_root.join('opnsense_backend')
      autoload :PfsenseBackend,          qga_root.join('pfsense_backend')
      autoload :UserScriptBackend,       qga_root.join('user_script_backend')
    end
  end
end
