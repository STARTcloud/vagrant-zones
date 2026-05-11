# frozen_string_literal: true

require 'base64'

module VagrantPlugins
  module ProviderZone
    module QGA
      # Mixin providing guest-exec orchestration on top of QGA::Client#request.
      # Including classes must define #request(execute, arguments, read_timeout:).
      module ClientExec
        # Run a command, wait for completion, return exitcode + stdout/stderr (decoded).
        def exec(path, args: nil, env: nil, input_data: nil, timeout: 120)
          pid = exec_start(path, args: args, env: env, input_data: input_data)
          deadline = Time.now + timeout
          loop do
            status = request('guest-exec-status', { pid: pid })
            return decode_exec(status) if status['exited']
            raise Errors::QGATimeout, message: "guest-exec '#{path}' did not exit within #{timeout}s" if Time.now > deadline

            sleep 1
          end
        end

        # Convenience: run a shell pipeline via /bin/sh -c.
        def shell(script, timeout: 120)
          exec('/bin/sh', args: ['-c', script], timeout: timeout)
        end

        private

        def exec_start(path, args: nil, env: nil, input_data: nil)
          arguments = { path: path, 'capture-output' => true }
          arguments[:arg] = args if args
          arguments[:env] = env if env
          arguments['input-data'] = Base64.strict_encode64(input_data) if input_data
          request('guest-exec', arguments)['pid']
        end

        def decode_exec(status)
          {
            exitcode: status['exitcode'],
            stdout: status['out-data'] ? Base64.decode64(status['out-data']) : '',
            stderr: status['err-data'] ? Base64.decode64(status['err-data']) : '',
            signal: status['signal']
          }
        end
      end
    end
  end
end
