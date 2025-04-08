require "rails"

module Tailwindcss
  class Engine < ::Rails::Engine
    config.before_configuration do |app|
      app.config.tailwindcss_rails = ActiveSupport::OrderedOptions.new
      app.config.tailwindcss_rails.engines = []
    end

    initializer 'tailwindcss.load_hook' do |app|
      ActiveSupport.run_load_hooks(:tailwindcss_rails, app)
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
