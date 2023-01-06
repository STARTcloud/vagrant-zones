# frozen_string_literal: true

require 'vagrant'

module VagrantPlugins
  module ProviderZone
    module Errors
      # Namespace for Vagrant Zones Errors
      class VagrantZonesError < Vagrant::Errors::VagrantError
        error_namespace('vagrant_zones.errors')
      end

      # System Check Results
      class SystemVersionIsTooLow < VagrantZonesError
        error_key(:system_version_too_low)
      end

      # Compatability Check Tool 
      class MissingCompatCheckTool < VagrantZonesError
        error_key(:missing_compatability_check_tool)
      end

      # Missing Bhyve
      class MissingBhyve < VagrantZonesError
        error_key(:missing_bhyve)
      end

      # HasNoRootPrivilege
      class HasNoRootPrivilege < VagrantZonesError
        error_key(:has_no_root_privilege)
      end

      # ExecuteError
      class ExecuteError < VagrantZonesError
        error_key(:execute_error)
      end

      # TimeoutError
      class TimeoutError < VagrantZonesError
        error_key(:timeout_error)
      end

      # VirtualBoxRunningConflictDetected
      class VirtualBoxRunningConflictDetected < VagrantZonesError
        error_key(:virtual_box_running_conflict_detected)
      end

      # NotYetImplemented
      class NotYetImplemented < VagrantZonesError
        error_key(:not_yet_implemented)
      end

      # TimeoutHalt
      class TimeoutHalt < VagrantZonesError
        error_key(:halt_timeout)
      end

      # InvalidbhyveBrand
      class InvalidbhyveBrand < VagrantZonesError
        error_key(:invalidbhyve_brand)
      end

      # InvalidLXBrand
      class InvalidLXBrand < VagrantZonesError
        error_key(:invalidLX_brand)
      end

      # ConsoleFailed
      class ConsoleFailed < VagrantZonesError
        error_key(:console_failed_exit)
      end
    end
  end
end
