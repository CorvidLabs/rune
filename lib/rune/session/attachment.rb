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
    # rubocop:disable Metrics/ClassLength -- the connect/handshake/pump/teardown sequence is one
    # linear story about a single socket, and splitting it would separate the raw-mode entry from
    # the restore that must pair with it.
    class Attachment
      # Ctrl-] — the long-standing telnet detach key, chosen because it is not
      # something an agent CLI binds. Ctrl-C must keep reaching the child, or an
      # attached human could not interrupt a runaway agent.
      DETACH_KEY = "\x1d"
      DETACH_HINT = 'Ctrl-] to detach (session keeps running)'
      CHUNK = 4096
      # Says what is known rather than asserting a cause. The attachment can
      # tell that output stopped; it cannot tell the difference between a child
      # that exited, a supervisor that was stopped, and an attachment dropped
      # for not keeping up, so it points at the command that can.
      ENDED_WHILE_ATTACHED = 'The attachment ended without detaching: the session stopped sending ' \
                             "output. Run 'rune session list' to see whether it is still running."

      def initialize(socket_path, input: $stdin, output: $stdout, announce: $stderr)
        @socket_path = socket_path
        @attached = false
        @detached = false
        @resized = false
        @input = input
        @output = output
        @announce = announce
      end

      def run
        socket = connect
        refusal = handshake(socket)
        return refusal if refusal

        @announce&.puts("[rune session] attached — #{DETACH_HINT}")
        @attached = true
        @detached = with_resize_forwarding { with_raw_terminal { pump(socket) } }
        return Result.failure(ENDED_WHILE_ATTACHED) unless @detached

        Result.success({ action: 'attach', detached: true })
      rescue Client::Unavailable => e
        Result.failure("Cannot attach: #{e.message}")
      ensure
        close_quietly(socket)
      end

      # Only when the human actually detached. Printing it whenever an
      # attachment had been established contradicted the failure the caller was
      # about to be shown: a session that ended underneath produced both
      # "detached; the session is still running" and "Session ended while
      # attached" in the same exit, one of which is always wrong. Reported from
      # real use against a grok session.
      def close_quietly(socket)
        socket.close unless socket.nil? || socket.closed?
        @announce&.puts("\n[rune session] detached; the session is still running.") if @detached
      rescue IOError, SystemCallError
        nil
      end

      private

      # Polled here rather than acted on inside the trap: a signal handler that
      # opens a socket and blocks on a reply is a good way to deadlock.
      def forward_pending_resize
        return unless @resized

        @resized = false
        forward_resize
      end

      # The local terminal's dimensions, when it has any. A detached session's
      # child was started headless at a fixed default, so without this an
      # attached human sees a full-screen agent laid out for someone else's
      # window inside their own.
      def terminal_size
        rows, cols = @input.winsize
        rows.to_i.positive? && cols.to_i.positive? ? { rows: rows, cols: cols } : {}
      rescue IOError, SystemCallError, NoMethodError
        {}
      end

      # Resize goes over its own short-lived connection: after the ack the
      # attachment socket is a raw byte pipe to the pty, so anything written
      # there would be typed at the child rather than interpreted.
      def forward_resize
        size = terminal_size
        return if size.empty?

        Client.new(@socket_path).request({ op: 'resize' }.merge(size))
      rescue Client::Unavailable
        nil
      end

      def with_resize_forwarding
        previous = trap('WINCH') { @resized = true }
        yield
      ensure
        trap('WINCH', previous || 'DEFAULT')
      end

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
        socket.puts(JSON.generate({ op: 'attach' }.merge(terminal_size)))
        socket.flush
        socket
      rescue SystemCallError => e
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
          forward_pending_resize
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
    # rubocop:enable Metrics/ClassLength
  end
end
