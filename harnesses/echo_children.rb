# frozen_string_literal: true

# Every child the settle rule has to be right about, in one place.
#
# Rule for probes: the *marker* must not appear anywhere in the input, or the
# echo alone satisfies the check and every case scores green for free. That
# mistake was made once here already (`puts 'NC3'` contains `NC3`).

SCRATCH = ENV.fetch('WORK')

CHILDREN = {
  # A reline line editor: repaints the whole line on submit, so the input is
  # on the wire a second time, and then goes quiet while the child thinks.
  'irb' => {
    command: %w[irb --nocolorize --prompt simple],
    probe: "sleep 3; puts 'N'+'C3'",
    marker: 'NC3',
    boot: 2.5
  },
  # Same shape, different line editor (python's own readline wrapper).
  'python' => {
    command: %w[python3 -q],
    probe: "import time; time.sleep(3); print('N'+'C3')",
    marker: 'NC3',
    boot: 2.0
  },
  # GNU readline in a shell: verbatim kernel-style echo, no repaint.
  'bash' => {
    command: %w[bash --norc --noprofile -i],
    probe: %q{sleep 3; echo N''C3},
    marker: 'NC3',
    boot: 1.0
  },
  # The same, past the 120-column window, so readline splits the echo with a
  # wrap the condensed search has to see through.
  'bash-wrap' => {
    command: %w[bash --norc --noprofile -i],
    probe: %(sleep 3; echo N''C3 # #{'x' * 140}),
    marker: 'NC3',
    boot: 1.0
  },
  # The spec's own child: its answer *ends with* the request, which is the
  # case that killed the last-copy anchor.
  'reply' => {
    command: ['ruby', '-e', <<~CHILD],
      STDOUT.sync = true
      while (line = STDIN.gets)
        sleep 1.0
        puts 'REPLY:' + line.strip
      end
    CHILD
    probe: 'ping',
    marker: 'REPLY:ping',
    boot: 0.5
  },
  # Answer ends with the request *and* arrives instantly, so there is no
  # thinking gap to hide behind.
  'reply-fast' => {
    command: ['ruby', '-e', <<~CHILD],
      STDOUT.sync = true
      while (line = STDIN.gets)
        puts 'REPLY:' + line.strip
      end
    CHILD
    probe: 'ping',
    marker: 'REPLY:ping',
    boot: 0.5
  },
  # ECHO off: nothing of the input comes back at all, and the answer is
  # immediate. A rule that withholds until it has found an echo hangs here.
  'noecho' => {
    command: ['ruby', '-e', <<~CHILD],
      require 'io/console'
      STDOUT.sync = true
      begin
        STDIN.echo = false
      rescue StandardError
        nil
      end
      while (line = STDIN.gets)
        puts 'ANSWER<' + line.strip + '>'
      end
    CHILD
    probe: 'ping',
    marker: 'ANSWER<ping>',
    boot: 0.5
  },
  # ECHO off and the answer *is* the request, verbatim, on its own line.
  'noecho-mirror' => {
    command: ['ruby', '-e', <<~CHILD],
      require 'io/console'
      STDOUT.sync = true
      begin
        STDIN.echo = false
      rescue StandardError
        nil
      end
      while (line = STDIN.gets)
        puts line.strip
        puts 'END'
      end
    CHILD
    probe: 'ping',
    marker: 'END',
    boot: 0.5
  },
  # A full-screen agent TUI: alt screen, raw mode, a composer it repaints on
  # every keystroke and a spinner that repaints the frame while it thinks.
  'tui' => {
    command: ['ruby', File.join(SCRATCH, 'tui_child.rb')],
    probe: 'ping',
    marker: 'DONE:ping',
    boot: 1.5
  },
  # The hard TUI: one frame on submit — the input painted into the transcript
  # — and then silence for the whole think. No spinner to keep it honest.
  'tui-quiet' => {
    command: ['ruby', File.join(SCRATCH, 'tui_child.rb'), '--quiet'],
    probe: 'ping',
    marker: 'DONE:ping',
    boot: 1.5
  },
  # zsh's line editor, which repaints like reline rather than echoing like
  # readline in bash.
  'zsh' => {
    command: %w[zsh -f -i],
    probe: %q{sleep 3; echo N''C3},
    marker: 'NC3',
    boot: 1.5
  },
  'zsh-wrap' => {
    command: %w[zsh -f -i],
    probe: %(sleep 3; echo N''C3 # #{'x' * 140}),
    marker: 'NC3',
    boot: 1.5
  },
  # A repaint that wraps: the second copy of the input is split across two
  # physical lines, so the "content after a line break" half of the rule is
  # looking straight at a repaint.
  'irb-wrap' => {
    command: %w[irb --nocolorize --prompt simple],
    probe: "sleep 3; puts 'N'+'C3' # #{'y' * 140}",
    marker: 'NC3',
    boot: 2.5
  },
  'python-wrap' => {
    command: %w[python3 -q],
    probe: "import time; time.sleep(3); print('N'+'C3') # #{'y' * 140}",
    marker: 'NC3',
    boot: 2.0
  },
  # The turn after a turn: the prompt on the line is the one the previous
  # answer left behind, not the one the banner drew.
  'irb-multi' => {
    command: %w[irb --nocolorize --prompt simple],
    pre: ['21 * 2'],
    probe: "sleep 3; puts 'N'+'C3'",
    marker: 'NC3',
    boot: 2.5
  },
  'python-multi' => {
    command: %w[python3 -q],
    pre: ['21 * 2'],
    probe: "import time; time.sleep(3); print('N'+'C3')",
    marker: 'NC3',
    boot: 2.0
  },
  # Nothing on stdout at all — only the shell's next prompt says the command
  # finished. A rule that suppresses redrawn prompts wholesale hangs here.
  'bash-silent' => {
    command: %w[bash --norc --noprofile -i],
    probe: 'sleep 3',
    marker: 'bash-',
    boot: 1.0
  },
  'zsh-silent' => {
    command: %w[zsh -f -i],
    probe: 'sleep 3',
    marker: '%',
    boot: 1.5
  },
  # ECHO off, a prompt on the line, and an answer that lands on that same line
  # rather than a new one.
  'noecho-inline' => {
    command: ['ruby', '-e', <<~CHILD],
      require 'io/console'
      STDOUT.sync = true
      begin
        STDIN.echo = false
      rescue StandardError
        nil
      end
      print '>>> '
      while (line = STDIN.gets)
        sleep 1.0
        print 'ANS<' + line.strip + '>'
        print "\\n>>> "
      end
    CHILD
    probe: 'ping',
    marker: 'ANS<ping>',
    boot: 0.5
  },
  # The echo arrives in pieces, several reads apart, which is what a long
  # prompt to a slow child looks like on the wire.
  'slow-echo' => {
    command: ['ruby', '-e', <<~CHILD],
      require 'io/console'
      STDOUT.sync = true
      begin
        STDIN.echo = false
      rescue StandardError
        nil
      end
      while (char = STDIN.getc)
        if char == "\\r" || char == "\\n"
          print "\\r\\n"
          sleep 2.0
          print 'ANSWER<done>' + "\\r\\n"
        else
          print char
          sleep 0.02
        end
      end
    CHILD
    probe: 'a-fairly-long-line-of-input-typed-slowly',
    marker: 'ANSWER<done>',
    boot: 0.5
  }
}.freeze
