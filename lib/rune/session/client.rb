# frozen_string_literal: true

require 'json'
require 'socket'
require_relative 'store'

module Rune
  module Session
    # One request/reply exchange against a session's control socket.
    #
    # The client deliberately holds no timeout of its own for `send`: the
    # supervisor already bounds the wait with `timeout_ms` and always replies,
    # including when it is shutting down (see `resolve_orphaned_pending`). A
    # second competing deadline here would race that one and produce two
    # different answers for the same call.
    class Client
      # Raised when the socket is missing or refuses a connection, which is how
      # a supervisor that died without cleanup presents itself.
      class Unavailable < StandardError; end

      def initialize(socket_path)
        @socket_path = socket_path
      end

      def request(payload)
        socket = connect
        socket.puts(JSON.generate(payload))
        socket.flush
        read_reply(socket)
      ensure
        socket&.close unless socket.nil? || socket.closed?
      end

      def available?
        connect.close
        true
      rescue Unavailable
        false
      end

      private

      def connect
        raise Unavailable, 'no control socket' unless File.socket?(@socket_path)

        Store.with_bindable_path(@socket_path) { |connectable| UNIXSocket.new(connectable) }
      rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPERM => e
        raise Unavailable, e.message
      end

      def read_reply(socket)
        line = socket.gets
        raise Unavailable, 'supervisor closed the connection without replying' if line.nil?

        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError => e
        raise Unavailable, "malformed reply: #{e.message}"
      end
    end
  end
end
