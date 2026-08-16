# Adversarial children for the bounded-tail-match change. Each is one shape the
# fix could plausibly get wrong.
$stdout.sync = true
mode = ARGV[0]

case mode
when 'repaint'
  # A full-screen agent: paints the prompt into a frame and redraws it many
  # times a second while it thinks, so the caller's own words keep reappearing
  # after the echo. The pattern the caller waits for is *inside* their input,
  # which is the case that forces the reverse scan on every tick.
  while (line = $stdin.gets)
    text = line.chomp
    60.times do
      print "\e[H\e[2J\e[1;36magent\e[0m\r\n  \e[35m>\e[0m #{text}\r\n\e[90m+#{'-' * 40}+\e[0m\r\n"
      print "\e[90m| thinking#{'.' * rand(3)}#{' ' * 30}|\e[0m\r\n"
      sleep 0.02
    end
    print "\e[H\e[2J  reply: the ANSWERTOKEN you asked about\r\n"
  end

when 'noecho'
  # ECHO off and raw keystrokes: nothing of the input ever reaches the wire, so
  # there is no echo to locate and the grace window has to expire.
  require 'io/console'
  begin
    $stdin.raw!
  rescue StandardError
    nil
  end
  buffer = +''
  loop do
    chunk = $stdin.readpartial(4096)
    buffer << chunk
    next unless buffer.include?("\r") || buffer.include?("\n")

    buffer = +''
    sleep 0.8
    print "silent child says ANSWERTOKEN\r\n"
  end

when 'quoteback'
  # Answers first and then quotes the request back, which is the case that
  # breaks if the echo boundary is moved to the *last* copy of the input.
  while (line = $stdin.gets)
    print "ANSWERTOKEN: finished\r\n(you asked: #{line.chomp})\r\n"
  end

when 'early'
  # Prints the marker almost immediately and then keeps talking for megabytes,
  # so a window that only ever looked at the tail would never see it.
  line = ("%-79s" % 'y') + "\n"
  while (cmd = $stdin.gets)
    mb = cmd.split[1].to_i
    print "ANSWERTOKEN\n"
    ((mb * 1024 * 1024) / line.bytesize).times { $stdout.write(line) }
    print "TRAILER\n"
  end

when 'spanning'
  # One match far longer than a single pty read: MB megabytes of filler between
  # OPEN and CLOSE, so `OPEN.*CLOSE` can only match by spanning all of it.
  line = ("%-79s" % 'z') + "\n"
  while (cmd = $stdin.gets)
    kb = cmd.split[1].to_i
    print "OPEN\n"
    ((kb * 1024) / line.bytesize).times { $stdout.write(line) }
    print "CLOSE\n"
  end

when 'lateecho'
  # Echoes the input back only after the grace window has closed, which is the
  # case the one-shot echo boundary gives up on and `repaint?` has to catch.
  require 'io/console'
  begin
    $stdin.raw!
  rescue StandardError
    nil
  end
  buffer = +''
  loop do
    chunk = $stdin.readpartial(4096)
    buffer << chunk
    next unless buffer.include?("\r") || buffer.include?("\n")

    text = buffer.split(/[\r\n]/).first.to_s
    buffer = +''
    sleep 1.2
    print "#{text}\r\n"   # the echo, long after the grace window
    sleep 1.0
    print "done\r\n"
  end
end
