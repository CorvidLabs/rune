# A child that emits N MB as fast as the pty will take it, then a marker.
#
# Deliberately line-oriented and cooked-mode: this is the shape that put the
# supervisor's regex wait in quadratic territory, because every tick re-scanned
# everything that had already arrived.
$stdout.sync = true
LINE = ("%-79s" % 'x') + "\n"          # 80 bytes
PER_MB = (1024 * 1024) / LINE.bytesize # lines per MiB

while (line = $stdin.gets)
  words = line.split
  next if words.empty?

  case words.first
  when 'emit'
    mb = words[1].to_i
    (mb * PER_MB).times { $stdout.write(LINE) }
    $stdout.write("RUNE-TURN-COMPLETE\n")
  when 'quit'
    exit 0
  else
    $stdout.write("RUNE-TURN-COMPLETE\n")
  end
end
