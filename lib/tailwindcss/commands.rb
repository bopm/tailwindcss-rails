require "tailwindcss/ruby"

module Tailwindcss
  module Commands
    class << self
      def rails_root
        defined?(Rails) ? Rails.root : Pathname.new(Dir.pwd)
      end

      def remove_tempfile!
        @@tempfile.unlink if @@tempfile
      end

      def compile_command(input: application_css, debug: false, **kwargs)
        debug = ENV["TAILWINDCSS_DEBUG"].present? if ENV.key?("TAILWINDCSS_DEBUG")

        command = [
          Tailwindcss::Ruby.executable(**kwargs),
          "-i", application_css,
          "-o", rails_root.join("app/assets/builds/tailwind.css").to_s,
        ]

        command << "--minify" unless (debug || rails_css_compressor?)

        postcss_path = rails_root.join("postcss.config.js")
        command += ["--postcss", postcss_path.to_s] if File.exist?(postcss_path)

        command
      end

      def application_css
        if engines_roots.any?
          @@tempfile = Tempfile.new("tailwind.application.css")
          engines_roots.each do |root|
            @@tempfile.puts "@import \"#{root}\";"
          end
          @@tempfile.puts "\n@import \"#{rails_root.join('app/assets/tailwind/application.css')}\";"
          @@tempfile.close

          @@tempfile.path
        else
          rails_root.join("app/assets/tailwind/application.css").to_s
        end
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

        Rails::Engine.subclasses.select do |engine|
          begin
            spec = Gem::Specification.find_by_name(engine.engine_name)
            spec.dependencies.any? { |d| d.name == 'tailwindcss-rails' }
          rescue Gem::MissingSpecError
            false
          end
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
