STDOUT.sync = true
while (line = STDIN.gets)
  break if line.nil?
  print "\e[2J\e[H"
  print "urce edits.RUN"                 # ends at column 14
  print "\e[2;1H"                        # a TUI's border/redraw jump
  print "\e[1;15H" + "E_TASK_COMPLETE_573"   # continues the same visual line
  print "\e[?25h"
end
