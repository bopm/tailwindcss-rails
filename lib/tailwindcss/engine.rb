require "rails"

module Tailwindcss
  class Engine < ::Rails::Engine
    initializer 'tailwindcss.add_engines_roots_config' do
      Rails.application.config.tailwindcss_rails.engines = []
    end

    initializer "tailwindcss.disable_generator_stylesheets" do
      Rails.application.config.generators.stylesheets = false
    end

    initializer "tailwindcss.exclude_asset_path", before: "propshaft.append_assets_path" do
      if Rails.application.config.assets.excluded_paths # the app may not be using Propshaft
        Rails.application.config.assets.excluded_paths << Rails.root.join("app/assets/tailwind")
      end
    end

    config.app_generators do |g|
      g.template_engine :tailwindcss
    end
  end
end
