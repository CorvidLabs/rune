# frozen_string_literal: true

require 'json'
require 'socket'
require 'io/wait'
require_relative 'store'

begin
  require 'io/console'
rescue LoadError
  nil
end

module Rune
  module Session
    # Connects a human's terminal to a live session: the child's output streams
    # to the screen and real keystrokes go back to it, until the detach key is
    # pressed. Detaching leaves the session running — that is the whole point,
    # and the difference between this and `rune watch`, which owns the child it
    # spawns and ends when that child ends.
    #
    # The pieces are deliberately the same shape as `PTYWatcher`'s (raw local
    # terminal, poll both directions, restore on the way out); the difference is
    # that the pty lives in another process, so the socket stands in for it.
    class Attachment
      # Ctrl-] — the long-standing telnet detach key, chosen because it is not
      # something an agent CLI binds. Ctrl-C must keep reaching the child, or an
      # attached human could not interrupt a runaway agent.
      DETACH_KEY = "\x1d"
      DETACH_HINT = 'Ctrl-] to detach (session keeps running)'
      CHUNK = 4096

      def initialize(socket_path, input: $stdin, output: $stdout, announce: $stderr)
        @socket_path = socket_path
        @input = input
        @output = output
        @announce = announce
      end

      def run
        socket = connect
        refusal = handshake(socket)
        return refusal if refusal

        @announce&.puts("[rune session] attached — #{DETACH_HINT}")
        Result.success({ action: 'attach', detached: with_raw_terminal { pump(socket) } })
      rescue Client::Unavailable => e
        Result.failure("Cannot attach: #{e.message}")
      ensure
        close_quietly(socket)
      end

      # The closing note is deliberately unconditional: leaving the session
      # running is the point of detaching, and a human who has just taken the
      # wheel of an agent needs telling that it is still out there.
      def close_quietly(socket)
        socket.close unless socket.nil? || socket.closed?
        @announce&.puts("\n[rune session] detached; the session is still running.")
      rescue IOError, SystemCallError
        nil
      end

      private

      # Returns a failure Result if the supervisor refused, nil to proceed.
      def handshake(socket)
        ack = JSON.parse(socket.gets.to_s, symbolize_names: true)
        ack[:error] ? Result.failure("Session refused the attach: #{ack[:error]}") : nil
      rescue JSON::ParserError
        Result.failure('Session sent a malformed attach acknowledgement.')
      end

      def connect
        raise Client::Unavailable, 'no control socket' unless File.socket?(@socket_path)

        socket = Store.with_bindable_path(@socket_path) { |path| UNIXSocket.new(path) }
        socket.puts(JSON.generate(op: 'attach'))
        socket.flush
        socket
      rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPERM => e
        raise Client::Unavailable, e.message
      end

      # Same rationale as PTYWatcher#with_raw_input: without raw mode the local
      # terminal echoes keystrokes itself and line-buffers them, so anything
      # without a trailing newline (arrow keys, single-key menus) never reaches
      # the remote child at all.
      def with_raw_terminal(&block)
        entered = false
        @input.raw do
          entered = true
          block.call
        end
      rescue Errno::ENOTTY, NoMethodError
        raise if entered

        block.call
      end

      def pump(socket)
        loop do
          ready = IO.select([@input, socket], nil, nil, 0.2)
          next unless ready

          ready[0].each do |io|
            return true if io.equal?(@input) && !forward_keystrokes(socket)

            return false if io.equal?(socket) && !render_output(socket)
          end
        end
      end

      # Returns false once the detach key is seen. Any bytes typed before it in
      # the same chunk are still delivered, so a detach never silently eats
      # input the child was meant to receive.
      def forward_keystrokes(socket)
        chunk = @input.readpartial(CHUNK)
        index = chunk.index(DETACH_KEY)
        payload = index ? chunk[0...index] : chunk
        unless payload.empty?
          socket.write(payload)
          socket.flush
        end
        index.nil?
      rescue IOError, SystemCallError
        false
      end

      def render_output(socket)
        chunk = socket.readpartial(CHUNK)
        @output.write(chunk)
        @output.flush
        true
      rescue IOError, SystemCallError
        false
      end
    end
  end
end
