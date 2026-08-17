#!/usr/bin/env ruby
# frozen_string_literal: true

# Measures the five renderer gaps ROADMAP.md still lists as open, so the fix
# order is decided by what actually breaks rather than by the order they were
# written down.
#
# Expectations come from ECMA-48 and xterm's own documentation, never from a
# reference emulator: `pyte` has been wrong against rune four times (no SU, no
# DECSTR, no `CSI u`, and it prints the final byte of a private-marker CSI), so
# a disagreement with a reference is a question, not a verdict.
#
#   ruby harnesses/renderer_gaps.rb
require_relative '../lib/rune'

ESC = "\e"

def render(text, rows: 4, columns: 20)
  Rune::Parsers::ScreenRenderer.render(text, rows: rows, columns: columns)
end

def probe(name, input, expected, why)
  actual = render(input)
  ok = yield(actual)
  puts format('  %-4s %s', ok ? 'ok' : 'GAP', name)
  return if ok

  puts "        want: #{expected}"
  puts "        got:  #{actual.lines.map(&:chomp).reject(&:empty?).inspect[0, 110]}"
  puts "        why:  #{why}"
end

puts "\nRenderer gaps, measured against ECMA-48 / xterm behaviour\n\n"

# 1. Alternate screen buffer. xterm: 1049 saves the cursor, switches to a
#    cleared alternate buffer, and restores the primary buffer on exit. An agent
#    CLI enters it at startup, so everything printed before it must not appear.
probe('alternate screen buffer (DECSET 1049)',
      "PRIMARY_TEXT\r\n#{ESC}[?1049hALT_TEXT",
      'only ALT_TEXT — the primary buffer is not visible while in the alternate one',
      'the alternate buffer is not modelled, so pre-switch output stays on the grid') do |out|
  out.include?('ALT_TEXT') && !out.include?('PRIMARY_TEXT')
end

probe('restoring the primary buffer (DECRST 1049)',
      "PRIMARY_TEXT\r\n#{ESC}[?1049hALT_TEXT#{ESC}[?1049l",
      'PRIMARY_TEXT again — the alternate buffer is discarded on exit',
      'without the alternate buffer there is nothing to restore') do |out|
  out.include?('PRIMARY_TEXT') && !out.include?('ALT_TEXT')
end

# 2. DECAWM. xterm: with autowrap off, a character written at the last column
#    replaces what is there and the cursor stays put — it does not wrap.
probe('autowrap off (DECRST 7)',
      "#{ESC}[?7l#{'A' * 25}",
      'a single row of 20 columns, the tail overwriting the last cell',
      'DECAWM is ignored, so the renderer wraps where a terminal would not') do |out|
  rows = out.lines.map(&:chomp).reject(&:empty?)
  rows.length == 1
end

# 3. Wide characters. Unicode East Asian Wide occupies two columns; a terminal
#    advances the cursor by two and never splits the pair.
# Written against an absolute column, because "日本語X" is what BOTH the correct
# and the naive renderer produce when X simply follows — the first version of
# this probe asserted exactly that and could not fail. Jumping to column 7 is
# what separates them: at two columns each the cursor is already there, and at
# one column each it is at 4 and three blanks appear.
probe('double-width characters occupy two columns',
      "#{ESC}[H日本語#{ESC}[1;7HX",
      '日本語X — the three glyphs used columns 1-6, so column 7 is the next cell',
      'each glyph advances one column, so an absolute column lands three cells late') do |out|
  out.lines.first.to_s.chomp.start_with?('日本語X')
end

# 4. DEC Special Graphics. `ESC ( 0` maps G0 to the line-drawing set, where
#    `q` is a horizontal line and `x` a vertical one; `ESC ( B` restores ASCII.
probe('DEC line drawing charset (ESC ( 0)',
      "#{ESC}(0qqq#{ESC}(Btext",
      'three horizontal-line glyphs then "text"',
      'the charset designation is dropped and the raw letters are printed') do |out|
  out.include?('───') || !out.include?('qqq')
end

# 5. IRM. With insert mode set, printing shifts the rest of the line right
#    rather than overwriting it.
probe('insert mode (IRM, CSI 4h)',
      "#{ESC}[HABCDEF#{ESC}[H#{ESC}[4hXY",
      'XYABCDEF — existing text shifted right',
      'IRM is not modelled, so the characters overwrite instead of inserting') do |out|
  out.lines.first.to_s.include?('XYABCDEF')
end

puts "\nControls — these must stay ok, they are what the gaps must not break:\n\n"

probe('plain text and wrapping still work',
      "#{'A' * 25}",
      'wraps at column 20 into two rows',
      'baseline') { |out| out.lines.map(&:chomp).reject(&:empty?).length == 2 }

probe('cursor positioning still works',
      "#{ESC}[2;3HXY",
      'XY at row 2, column 3',
      'baseline') { |out| out.lines[1].to_s.start_with?('  XY') }

# The double-width gap has had one attempt, reverted. These are the cases that
# killed it: a cell model that stores a wide glyph as base + continuation works
# until any other grid operation touches the row, because they all manipulate
# the String directly and know nothing about the pair. Kept as the acceptance
# test for the next attempt, which needs a grid of cells rather than a String.
puts "\nWhat a wide-character cell model has to survive (see parsers.spec.md invariant 17):\n\n"
puts "  These print the CURRENT one-column behaviour, the baseline to beat. The reverted cell\n"
puts "  model changed two of them, both for the worse: 'erase one cell inside a pair' became\n"
puts "  \"東 京AB\" and 'repaint over the left half' became \"h 京AB\" — an orphan continuation\n"
puts "  cell rendering as a space. The other three were identical, so they are baseline only.\n\n"

{
  'delete a char before a wide pair' => "#{ESC}[H東京AB#{ESC}[1;1H#{ESC}[P",
  'insert a blank before a pair' => "#{ESC}[H東京AB#{ESC}[1;1H#{ESC}[@",
  'erase one cell inside a pair' => "#{ESC}[H東京AB#{ESC}[1;2H#{ESC}[X",
  'repaint over the left half' => "#{ESC}[H東京AB#{ESC}[1;1Hh",
  'erase to end from mid-pair' => "#{ESC}[H東京AB#{ESC}[1;2H#{ESC}[K"
}.each do |name, input|
  puts format('  %-34s -> %s', name, render(input, rows: 3, columns: 12).inspect)
end
