require "test_helper"
require "ostruct"
require "tmpdir"
require "rails/engine"

class Tailwindcss::CommandsTest < ActiveSupport::TestCase
  setup do
    @tmp_dir = Dir.mktmpdir
    @original_rails = Object.const_get(:Rails) if Object.const_defined?(:Rails)
    @executable = Tailwindcss::Ruby.executable
  end

  teardown do
    FileUtils.rm_rf(@tmp_dir)
    Tailwindcss::Commands.remove_tempfile! if Tailwindcss::Commands.class_variable_defined?(:@@tempfile)
    restore_rails_constant
  end

  test "compile command includes basic options" do
    with_rails_app do
      command = Tailwindcss::Commands.compile_command

      assert_equal @executable, command.first
      assert_includes command, "-i"
      assert_includes command, "-o"
      assert_includes command, "--minify"
    end
  end

  test "compile command respects debug flag" do
    with_rails_app do
      debug_command = Tailwindcss::Commands.compile_command(debug: true)
      refute_includes debug_command, "--minify"
    end
  end

  test "compile command respects TAILWINDCSS_DEBUG env var" do
    with_rails_app do
      ENV["TAILWINDCSS_DEBUG"] = "1"
      command = Tailwindcss::Commands.compile_command
      refute_includes command, "--minify"
    ensure
      ENV.delete("TAILWINDCSS_DEBUG")
    end
  end

  test "watch command includes correct options" do
    with_rails_app do
      command = Tailwindcss::Commands.watch_command

      assert_equal @executable, command.first
      assert_includes command, "-w"
      assert_includes command, "--minify"
      refute_includes command, "-p"
    end
  end

  test "watch command with poll option" do
    with_rails_app do
      command = Tailwindcss::Commands.watch_command(poll: true)
      assert_includes command, "-p"
    end
  end

  test ".engines_roots when there are engines" do
    within_engine_configs do |engine1, engine2, engine3|
      roots = Tailwindcss::Commands.engines_roots

      assert_equal 2, roots.size
      assert_includes roots, engine1.css_path.to_s
      assert_includes roots, engine2.css_path.to_s
      refute_includes roots, engine3.css_path.to_s
    end
  end

  test ".engines_roots when Rails is not defined" do
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
    assert_empty Tailwindcss::Commands.engines_roots
  end

  test ".engines_roots when no engines are configured" do
    with_rails_app do
      assert_empty Tailwindcss::Commands.engines_roots
    end
  end

  test ".rails_css_compressor? when css_compressor is not configured" do
    with_rails_app do
      Rails.application.config.assets.css_compressor = nil
      refute Tailwindcss::Commands.rails_css_compressor?
    end
  end

  test ".command_env with verbose flag" do
    env = Tailwindcss::Commands.command_env(verbose: true)
    assert_equal "1", env["DEBUG"]
  end

  test ".command_env without verbose flag" do
    env = Tailwindcss::Commands.command_env(verbose: false)
    assert_empty env
  end

  test ".application_css creates tempfile when engines exist" do
    within_engine_configs do |engine1, engine2|
      css_path = Tailwindcss::Commands.application_css

      assert_match(/tailwind\.application\.css/, css_path)
      assert File.exist?(css_path)

      content = File.read(css_path)
      assert_match %r{@import "#{engine1.css_path}";}, content
      assert_match %r{@import "#{engine2.css_path}";}, content
      assert_match %r{@import "#{Rails.root.join('app/assets/tailwind/application.css')}";}, content
    end
  end

  test ".application_css returns application.css path when no engines" do
    with_rails_app do
      expected_path = Rails.root.join("app/assets/tailwind/application.css").to_s
      assert_equal expected_path, Tailwindcss::Commands.application_css
    end
  end

  test ".application_css handles tempfile cleanup" do
    within_engine_configs do
      css_path = Tailwindcss::Commands.application_css
      assert File.exist?(css_path)

      Tailwindcss::Commands.remove_tempfile!
      refute File.exist?(css_path)
    end
  end

  test "engines can be configured via ActiveSupport.on_load" do
    with_rails_app do
      # Create a test engine
      test_engine = Class.new(Rails::Engine) do
        def self.engine_name
          "test_engine"
        end

        def self.root
          Pathname.new(Dir.mktmpdir)
        end
      end

      # Create CSS file for the engine
      engine_css_path = test_engine.root.join("app/assets/tailwind/test_engine/application.css")
      FileUtils.mkdir_p(File.dirname(engine_css_path))
      FileUtils.touch(engine_css_path)

      # Create application-level CSS file
      app_css_path = Rails.root.join("app/assets/tailwind/test_engine/application.css")
      FileUtils.mkdir_p(File.dirname(app_css_path))
      FileUtils.touch(app_css_path)

      # Register the engine
      Rails::Engine.descendants << test_engine

      # Store the hook for later execution
      hook = nil
      ActiveSupport.on_load(:tailwindcss_rails) do
        hook = self
        Rails.application.config.tailwindcss_rails.engines << "test_engine"
      end

      # Trigger the hook manually
      ActiveSupport.run_load_hooks(:tailwindcss_rails, hook)

      # Verify the engine is included in roots
      roots = Tailwindcss::Commands.engines_roots
      assert_equal 1, roots.size
      assert_includes roots, app_css_path.to_s
    ensure
      FileUtils.rm_rf(test_engine.root) if defined?(test_engine)
      FileUtils.rm_rf(File.dirname(app_css_path)) if defined?(app_css_path)
    end
  end

  private
    def with_rails_app
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
      Object.const_set(:Rails, setup_mock_rails)
      yield
    end

    def setup_mock_rails
      mock_engine = Class.new do
        class << self
          attr_accessor :engine_name, :root

          def descendants
            @descendants ||= []
          end
        end
      end

      mock_rails = Class.new do
        class << self
          attr_accessor :root, :application

          def const_get(const_name)
            return Engine if const_name == :Engine
            super
          end
        end
      end

      mock_rails.const_set(:Engine, mock_engine)
      mock_rails.root = Pathname.new(@tmp_dir)
      mock_rails.application = OpenStruct.new(
        config: OpenStruct.new(
          tailwindcss_rails: OpenStruct.new(engines: []),
          assets: OpenStruct.new(css_compressor: nil)
        )
      )
      mock_rails
    end

    def restore_rails_constant
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
      Object.const_set(:Rails, @original_rails) if @original_rails
    end

    def within_engine_configs
      engine_configs = create_test_engines
      with_rails_app do
        Rails.application.config.tailwindcss_rails.engines = %w[test_engine1 test_engine2]

        # Create and register mock engine classes
        engine_configs.each do |config|
          engine_class = Class.new(Rails::Engine)
          engine_class.engine_name = config.name
          engine_class.root = Pathname.new(config.root)
          Rails::Engine.descendants << engine_class
        end

        yield(*engine_configs)
      end
    end

    def create_test_engines
      [1, 2, 3].map do |i|
        engine = OpenStruct.new
        engine.name = "test_engine#{i}"
        engine.root = File.join(@tmp_dir, "engine#{i}")
        engine.css_path = File.join(@tmp_dir, "app/assets/tailwind/test_engine#{i}/application.css")
        FileUtils.mkdir_p(File.dirname(engine.css_path))
        FileUtils.touch(engine.css_path)
        engine
      end
    end
end
