# frozen_string_literal: true

require 'log4r'

module VagrantPlugins
  module ProviderZone
    module SetupStrategies
      # Shared initialization for setup strategies. Each subclass implements
      # wait_for_boot(uii, metrics, interrupted), get_ip_address(uii),
      # setup_network(uii), and control(uii, action) via duck typing.
      class Base
        def initialize(driver)
          @driver = driver
          @machine = driver.machine
          @logger = Log4r::Logger.new("vagrant_zones::strategy::#{self.class.name.split('::').last.downcase}")
        end
      end
    end
  end
end
