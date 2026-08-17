STDOUT.sync = true
while (line = STDIN.gets)
  break if line.nil?
  print "\e[2J\e[H"
  # Fill to the right margin so the token wraps onto the NEXT ROW, the way a
  # 120-column terminal does. No cursor positioning at all.
  print ("x" * 117) + "RUNE_TASK_COMPLETE_573\n"
end
