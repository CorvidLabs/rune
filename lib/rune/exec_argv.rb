# frozen_string_literal: true

module Rune
  # Turns a caller's command into arguments `Kernel#spawn` will treat the way
  # the caller meant.
  #
  # Ruby routes a spawn through `/bin/sh` whenever it receives a single String
  # containing a shell metacharacter — and splatting a one-element array is
  # exactly that. So an **argv array** of one element was silently shelled:
  # `rune run -- "/opt/my program"` executed `/opt/my`, reported
  # `status: ok, exit_code: 0`, and `rune run -- 'echo A; echo B'` ran both
  # commands. `--` is documented as the fence past which the wrapped command's
  # argv passes through untouched, so the path the docs teach as the explicit,
  # safe one was a shell-injection sink for any wrapper interpolating a command.
  #
  # A **String** command is a different contract and keeps its old meaning:
  # `PTYRunner.new('sleep 1')` is documented to take a command line, and
  # splitting or exec'ing it literally would break every caller of that form.
  # Only the array form promises argv fidelity, so only the array form is
  # forced to exec — via `[cmdname, argv0]`, Ruby's own idiom for "this exact
  # file, never a shell". Arrays of two or more were already safe.
  module ExecArgv
    module_function

    # `argv:` is whether the caller passed an array, not whether one element
    # happens to be left: that is the whole distinction, and inferring it from
    # the length is what produced the bug.
    def for_spawn(arguments, argv:)
      return arguments unless argv && arguments.length == 1

      [[arguments.first, arguments.first]]
    end
  end
end
