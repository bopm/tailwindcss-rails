require "tailwindcss/ruby"

module Tailwindcss
  module Commands
    class << self
      def rails_root
        defined?(Rails) ? Rails.root : Pathname.new(Dir.pwd)
      end

      def remove_tempfile!
        return unless class_variable_defined?(:@@tempfile) && @@tempfile

        @@tempfile.close unless @@tempfile.closed?
        @@tempfile.unlink if File.exist?(@@tempfile.path)
        remove_class_variable(:@@tempfile)
      end

      def compile_command(input: application_css, debug: false, **kwargs)
        debug = ENV["TAILWINDCSS_DEBUG"].present? if ENV.key?("TAILWINDCSS_DEBUG")

        command = [
          Tailwindcss::Ruby.executable(**kwargs),
          "-i", input.to_s,
          "-o", rails_root.join("app/assets/builds/tailwind.css").to_s,
        ]

        command << "--minify" unless (debug || rails_css_compressor?)

        postcss_path = rails_root.join("postcss.config.js")
        command += ["--postcss", postcss_path.to_s] if File.exist?(postcss_path)

        command
      end

      def application_css
        return rails_root.join("app/assets/tailwind/application.css").to_s if engines_roots.empty?

        @@tempfile = Tempfile.new("tailwind.application.css")

        # Write content to tempfile
        engines_roots.each do |root|
          @@tempfile.write("@import \"#{root}\";\n")
        end
        @@tempfile.write("\n@import \"#{rails_root.join('app/assets/tailwind/application.css')}\";\n")
        @@tempfile.flush
        @@tempfile.close

        @@tempfile.path
      end

      def watch_command(always: false, poll: false, **kwargs)
        compile_command(**kwargs).tap do |command|
          command << "-w"
          command << "always" if always
          command << "-p" if poll
        end
      end

      def command_env(verbose:)
        {}.tap do |env|
          env["DEBUG"] = "1" if verbose
        end
      end

      def rails_css_compressor?
        defined?(Rails) && Rails&.application&.config&.assets&.css_compressor.present?
      end

      def engines_roots
        return [] unless defined?(Rails)
        return [] unless Rails.application&.config&.tailwindcss_rails&.engines

        Rails::Engine.descendants.select do |engine|
          engine.engine_name.in?(Rails.application.config.tailwindcss_rails.engines)
        end.map do |engine|
          [
            rails_root.join("app/assets/tailwind/#{engine.engine_name}/application.css"),
            engine.root.join("app/assets/tailwind/#{engine.engine_name}/application.css")
          ].select(&:exist?).compact.first.to_s
        end.compact
      end
    end
  end
end
