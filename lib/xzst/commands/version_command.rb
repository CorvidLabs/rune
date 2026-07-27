# frozen_string_literal: true

module XZST
  module Commands
    class VersionCommand < Command
      name 'version'
      summary 'Show xzst version and environment info'

      def call(_args, _options)
        Result.success({
                         name: 'xzst',
                         version: VERSION,
                         ruby: RUBY_VERSION,
                         ruby_platform: RUBY_PLATFORM,
                         fledge: fledge_available?,
                         specsync: specsync_available?
                       })
      end

      def human_render(data, io)
        io.puts "\e[1;35mxzst\e[0m v#{data[:version]}"
        io.puts "  Ruby #{data[:ruby]} (#{data[:ruby_platform]})"
        io.puts "  fledge:    #{status_icon(data[:fledge])}"
        io.puts "  spec-sync: #{status_icon(data[:specsync])}"
      end

      private

      def fledge_available?
        system('which fledge > /dev/null 2>&1')
      end

      def specsync_available?
        system('which specsync > /dev/null 2>&1')
      end

      def status_icon(available)
        available ? "\e[32m✓ available\e[0m" : "\e[33m○ not found\e[0m"
      end
    end
  end
end
