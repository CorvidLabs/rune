STDOUT.sync = true
while (line = STDIN.gets)
  break if line.nil?
  text = line.strip
  print "\e[2J\e[H"
  print "\e[1;1H" + "-" * 60 + "\n"
  print "| " + text + "\n"                 # the composer echoing the prompt
  print "-" * 60 + "\n"
  sleep 4                                   # thinking, printing nothing
  print "\e[2J\e[HRUNE_TASK_COMPLETE_573 real answer\n"
end
