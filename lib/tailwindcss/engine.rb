require "rails"

module Tailwindcss
  class Engine < ::Rails::Engine
    class << self
      def globs
        (Rails.application.config.assets.tailwind_roots.flat_map do |path|
          Rails.application.config.assets.tailwind_source_paths.map { |source| "#{path}/#{source}" }
        end + Rails.application.config.assets.tailwind_custom_paths).uniq
      end
    end

    initializer "tailwindcss.assets" do
      Rails.application.config.assets.precompile += %w( inter-font.css )
      Rails.application.config.assets.tailwind_source_paths = %w( public/*.html app/helpers/**/*.rb app/javascript/**/*.js app/views/**/*.{erb,haml,html,slim} )
      Rails.application.config.assets.tailwind_roots = [Rails.root]
      Rails.application.config.assets.tailwind_custom_paths = []
    end

    initializer "tailwindcss.disable_generator_stylesheets" do
      Rails.application.config.generators.stylesheets = false
    end

    config.app_generators do |g|
      g.template_engine :tailwindcss
    end
  end
end
