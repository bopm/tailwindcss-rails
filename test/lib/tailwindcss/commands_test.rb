require "test_helper"
require "minitest/mock"
require "tmpdir"
require "ostruct"
require "active_support/core_ext/class/subclasses"

class Tailwindcss::CommandsTest < ActiveSupport::TestCase
  attr_accessor :executable

  def setup
    super
    @executable = Tailwindcss::Ruby.executable
  end

  def teardown
    super
    if Tailwindcss::Commands.class_variable_defined?(:@@tempfile)
      Tailwindcss::Commands.remove_tempfile!
    end
  end

  def with_rails_mocks(root: Pathname.new(Dir.mktmpdir), engines: [])
    mock_config = Object.new
    def mock_config.tailwindcss_rails
      @tailwindcss_rails ||= OpenStruct.new(engines: @engines)
    end
    def mock_config.assets
      @assets ||= OpenStruct.new(css_compressor: nil)
    end
    mock_config.instance_variable_set(:@engines, engines)

    mock_application = Object.new
    def mock_application.config
      @config
    end
    mock_application.instance_variable_set(:@config, mock_config)

    Rails.stub(:root, root) do
      Rails.stub(:application, mock_application) do
        yield
      end
    end
  end

  test ".compile_command" do
    with_rails_mocks do
      actual = Tailwindcss::Commands.compile_command
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-i")
      assert_includes(actual, "-o")
    end
  end

  test ".compile_command debug flag" do
    with_rails_mocks do
      actual = Tailwindcss::Commands.compile_command
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "--minify")

      actual = Tailwindcss::Commands.compile_command(debug: true)
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      refute_includes(actual, "--minify")
    end
  end

  test ".compile_command debug environment variable" do
    begin
      with_rails_mocks do
        ENV["TAILWINDCSS_DEBUG"] = ""
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        assert_includes(actual, "--minify")

        actual = Tailwindcss::Commands.compile_command(debug: true)
        assert_kind_of(Array, actual)
        assert_includes(actual, "--minify")

        ENV["TAILWINDCSS_DEBUG"] = "any non-blank value"
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        refute_includes(actual, "--minify")

        actual = Tailwindcss::Commands.compile_command(debug: true)
        assert_kind_of(Array, actual)
        refute_includes(actual, "--minify")
      end
    ensure
      ENV.delete('TAILWINDCSS_DEBUG')
    end
  end

  test ".compile_command when Rails compression is on" do
    with_rails_mocks do
      Tailwindcss::Commands.stub(:rails_css_compressor?, true) do
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        refute_includes(actual, "--minify")
      end

      Tailwindcss::Commands.stub(:rails_css_compressor?, false) do
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        assert_includes(actual, "--minify")
      end
    end
  end

  test ".compile_command when postcss.config.js exists" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      with_rails_mocks(root: root) do
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        assert_equal(executable, actual.first)
        refute_includes(actual, "--postcss")

        config_file = root.join("postcss.config.js")
        FileUtils.touch(config_file)
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        assert_equal(executable, actual.first)
        assert_includes(actual, "--postcss")
        postcss_index = actual.index("--postcss")
        assert_equal(actual[postcss_index + 1], config_file.to_s)
      end
    end
  end

  test ".watch_command" do
    with_rails_mocks do
      actual = Tailwindcss::Commands.watch_command
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-w")
      refute_includes(actual, "-p")
      assert_includes(actual, "--minify")

      actual = Tailwindcss::Commands.watch_command(debug: true)
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-w")
      refute_includes(actual, "-p")
      refute_includes(actual, "--minify")

      actual = Tailwindcss::Commands.watch_command(poll: true)
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-w")
      refute_includes(actual, "always")
      assert_includes(actual, "-p")
      assert_includes(actual, "--minify")

      actual = Tailwindcss::Commands.watch_command(always: true)
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-w")
      assert_includes(actual, "always")
    end
  end

  test ".engines_roots when there are no engines" do
    with_rails_mocks do
      Rails::Engine.stub(:subclasses, []) do
        assert_empty Tailwindcss::Commands.engines_roots
      end
    end
  end

  test ".engines_roots when there are engines" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      # Create multiple engines
      engine_root1 = root.join('engine1')
      engine_root2 = root.join('engine2')
      engine_root3 = root.join('engine3')
      FileUtils.mkdir_p(engine_root1)
      FileUtils.mkdir_p(engine_root2)
      FileUtils.mkdir_p(engine_root3)

      engine1 = Class.new(Rails::Engine) do
        define_singleton_method(:engine_name) { "test_engine1" }
        define_singleton_method(:root) { engine_root1 }
      end

      engine2 = Class.new(Rails::Engine) do
        define_singleton_method(:engine_name) { "test_engine2" }
        define_singleton_method(:root) { engine_root2 }
      end

      engine3 = Class.new(Rails::Engine) do
        define_singleton_method(:engine_name) { "test_engine3" }
        define_singleton_method(:root) { engine_root3 }
      end

      # Set up file structure
      engine1_css = engine_root1.join("app/assets/tailwind/test_engine1/application.css")
      engine2_css = root.join("app/assets/tailwind/test_engine2/application.css")
      engine3_css = engine_root2.join("app/assets/tailwind/test_engine3/application.css")

      [engine1_css, engine2_css, engine3_css].each do |css_path|
        FileUtils.mkdir_p(File.dirname(css_path))
        FileUtils.touch(css_path)
      end

      with_rails_mocks(root: root, engines: %w[test_engine1 test_engine2]) do
        Rails::Engine.stub(:descendants, [engine1, engine2, engine3]) do
          roots = Tailwindcss::Commands.engines_roots

          assert_equal 2, roots.size
          assert_includes roots, engine1_css.to_s
          assert_includes roots, engine2_css.to_s
          assert_not_includes roots, engine3_css.to_s
        end
      end
    end
  end

  test ".application_css creates tempfile when engines exist" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      # Create engine files
      engine_root = root.join('engine1')
      FileUtils.mkdir_p(engine_root)

      engine = Class.new(Rails::Engine) do
        define_singleton_method(:engine_name) { "test_engine" }
        define_singleton_method(:root) { engine_root }
      end

      app_css = root.join("app/assets/tailwind/application.css")
      engine_css = engine_root.join("app/assets/tailwind/test_engine/application.css")

      FileUtils.mkdir_p(File.dirname(app_css))
      FileUtils.mkdir_p(File.dirname(engine_css))
      FileUtils.touch(app_css)
      FileUtils.touch(engine_css)

      with_rails_mocks(root: root, engines: ["test_engine"]) do
        Rails::Engine.stub(:descendants, [engine]) do
          Tailwindcss::Commands.remove_tempfile!
          css_path = Tailwindcss::Commands.application_css

          assert File.exist?(css_path), "Tempfile should exist"
          content = File.read(css_path)
          expected_content = <<~CSS
            @import "#{engine_css}";
  
            @import "#{app_css}";
          CSS
          assert_equal expected_content, content
        end
      end
    end
  end

  test ".application_css uses application.css when no engines exist" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      app_css = root.join("app/assets/tailwind/application.css")
      FileUtils.mkdir_p(File.dirname(app_css))
      FileUtils.touch(app_css)

      with_rails_mocks(root: root) do
        css_path = Tailwindcss::Commands.application_css
        assert_equal app_css.to_s, css_path
      end
    end
  end

  test ".remove_tempfile! cleans up temporary file" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      app_css = root.join("app/assets/tailwind/application.css")
      FileUtils.mkdir_p(File.dirname(app_css))
      FileUtils.touch(app_css)

      with_rails_mocks(root: root, engines: ["test_engine"]) do
        Tailwindcss::Commands.remove_tempfile!
        css_path = Tailwindcss::Commands.application_css
        assert File.exist?(css_path), "Tempfile should exist before removal"

        Tailwindcss::Commands.remove_tempfile!
        refute File.exist?(css_path), "Tempfile should not exist after removal"
      end
    end
  end
end
