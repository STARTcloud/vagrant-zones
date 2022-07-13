# frozen_string_literal: true

require 'vagrant/util/busy'
require 'vagrant/util/subprocess'

module VagrantPlugins
  module ProviderZone
    module Executor
      # This class is used to execute commands as subprocess.
      class Exec
        # When we need the command's exit code we should set parameter
        # exit_code to true, otherwise this method will return executed
        # command's stdout
        def execute(exit_code, *cmd, **_opts, &block)
          # Append in the options for subprocess
          cmd << { notify: %i[stdout stderr] }

          cmd.unshift('sh', '-c')
          interrupted = false
          # Lambda to change interrupted to true
          int_callback = -> { interrupted = true }
          result = ::Vagrant::Util::Busy.busy(int_callback) do
            ::Vagrant::Util::Subprocess.execute(*cmd, &block)
          end
          return result.exit_code if exit_code

          result.stderr.gsub!("\r\n", "\n")
          result.stdout.gsub!("\r\n", "\n")
          puts "Command Failed: #{cmd}" if result.exit_code != 0 || interrupted
          puts "Exit Results: #{result.stderr}" if result.exit_code != 0 || interrupted
          raise Errors::ExecuteError if result.exit_code != 0 || interrupted

          result.stdout[0..-2]
        end
      end
    end
  end
end
