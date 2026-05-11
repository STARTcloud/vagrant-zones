# frozen_string_literal: true

require 'pathname'

module VagrantPlugins
  module ProviderZone
    # Setup strategy submodule: each strategy implements wait_for_boot, get_ip_address,
    # setup_network, and control(action) for one setup_method value. Mixins under this
    # namespace factor out PTY console, netplan, dladm, and Windows helpers used by Zlogin.
    module SetupStrategies
      strategies_root = Pathname.new(File.expand_path('setup_strategies', __dir__))
      autoload :Base,                  strategies_root.join('base')
      autoload :ZloginConsole,         strategies_root.join('zlogin_console')
      autoload :ZloginWindowsConsole,  strategies_root.join('zlogin_windows_console')
      autoload :ZloginNetplan,         strategies_root.join('zlogin_netplan')
      autoload :ZloginDladm,           strategies_root.join('zlogin_dladm')
      autoload :ZloginWindows,         strategies_root.join('zlogin_windows')
      autoload :Zlogin,                strategies_root.join('zlogin')
      autoload :DHCP,                  strategies_root.join('dhcp')
      autoload :QGA,                   strategies_root.join('qga')
    end
  end
end
