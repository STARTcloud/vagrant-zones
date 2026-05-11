# frozen_string_literal: true

require 'base64'
require 'json'
require 'socket'
require 'timeout'

module VagrantPlugins
  module ProviderZone
    module QGA
      # JSON-RPC client speaking the QEMU Guest Agent protocol over a UNIX socket.
      # One socket per request to avoid stale buffers and partial reads.
      # TODO(qga-abort): wire guest-exec-cancel on SIGINT mid-exec.
      class Client
        include ClientExec

        DEFAULT_READ_TIMEOUT = 30
        PING_READ_TIMEOUT = 5

        attr_reader :socket_path

        def initialize(socket_path)
          @socket_path = socket_path
        end

        def socket_present?
          File.exist?(@socket_path) && File.socket?(@socket_path)
        end

        def wait_for_socket(timeout)
          deadline = Time.now + timeout
          loop do
            return if socket_present?
            raise Errors::QGATimeout, message: "qga.sock not present after #{timeout}s at #{@socket_path}" if Time.now > deadline

            sleep 1
          end
        end

        def wait_for_ready(timeout)
          deadline = Time.now + timeout
          loop do
            return if ping
            raise Errors::QGATimeout, message: "guest-ping did not respond within #{timeout}s" if Time.now > deadline

            sleep 2
          end
        end

        def request(execute, arguments = nil, read_timeout: DEFAULT_READ_TIMEOUT)
          payload = { execute: execute }
          payload[:arguments] = arguments if arguments
          sock = UNIXSocket.new(@socket_path)
          begin
            sock.write("#{JSON.generate(payload)}\n")
            sock.flush
            line = nil
            Timeout.timeout(read_timeout) { line = sock.gets }
            raise Errors::QGAError, message: "empty response from qga (#{execute})" if line.nil? || line.strip.empty?

            response = JSON.parse(line)
            raise Errors::QGAError, message: "#{execute}: #{response['error']}" if response['error']

            response['return']
          ensure
            sock.close
          end
        rescue Errno::ENOENT, Errno::ECONNREFUSED => e
          raise Errors::QGAError, message: "qga socket unavailable: #{e.message}"
        rescue Timeout::Error
          raise Errors::QGATimeout, message: "qga read timeout for #{execute}"
        end

        def ping
          request('guest-ping', nil, read_timeout: PING_READ_TIMEOUT)
          true
        rescue StandardError
          false
        end

        def info
          request('guest-info')
        end

        def osinfo
          request('guest-get-osinfo')
        end

        def hostname
          request('guest-get-host-name')
        end

        def network_interfaces
          request('guest-network-get-interfaces')
        end

        def set_user_password(username, password, crypted: false)
          request('guest-set-user-password', {
                    username: username,
                    password: Base64.strict_encode64(password),
                    crypted: crypted
                  })
        end

        def shutdown(mode = 'powerdown')
          request('guest-shutdown', { mode: mode })
        rescue Errors::QGAError, Errors::QGATimeout
          # Guest disconnects mid-shutdown; treat as success.
          nil
        end
      end
    end
  end
end
