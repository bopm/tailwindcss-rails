require "test_helper"
require "minitest/mock"

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

  test ".compile_command" do
    Rails.stub(:root, File) do # Rails.root won't work in this test suite
      actual = Tailwindcss::Commands.compile_command
      assert_kind_of(Array, actual)
      assert_equal(executable, actual.first)
      assert_includes(actual, "-i")
      assert_includes(actual, "-o")
    end
  end

  test ".compile_command debug flag" do
    Rails.stub(:root, File) do # Rails.root won't work in this test suite
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
      Rails.stub(:root, File) do # Rails.root won't work in this test suite
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
    Rails.stub(:root, File) do # Rails.root won't work in this test suite
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
      Rails.stub(:root, Pathname.new(tmpdir))  do # Rails.root won't work in this test suite
        actual = Tailwindcss::Commands.compile_command
        assert_kind_of(Array, actual)
        assert_equal(executable, actual.first)
        refute_includes(actual, "--postcss")

        config_file = Rails.root.join("postcss.config.js")
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
    Rails.stub(:root, File) do # Rails.root won't work in this test suite
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
    Rails.stub(:root, Pathname.new("/dummy")) do
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

      # Create mock specs for engines
      spec1 = Minitest::Mock.new
      spec1.expect(:dependencies, [Gem::Dependency.new("tailwindcss-rails")])

      spec2 = Minitest::Mock.new
      spec2.expect(:dependencies, [Gem::Dependency.new("tailwindcss-rails")])

      spec3 = Minitest::Mock.new
      spec3.expect(:dependencies, [])

      # Set up file structure
      engine1_css = engine_root1.join("app/assets/tailwind/test_engine1/application.css")
      engine2_css = root.join("app/assets/tailwind/test_engine2/application.css")
      engine3_css = engine_root2.join("app/assets/tailwind/test_engine3/application.css")

      [engine1_css, engine2_css, engine3_css].each do |css_path|
        FileUtils.mkdir_p(File.dirname(css_path))
        FileUtils.touch(css_path)
      end

      find_by_name_results = {
        "test_engine1" => spec1,
        "test_engine2" => spec2,
        "test_engine3" => spec3,
      }

      Gem::Specification.stub(:find_by_name, ->(name) { find_by_name_results[name] }) do
        Rails.stub(:root, root) do
          Rails::Engine.stub(:subclasses, [engine1, engine2]) do
            roots = Tailwindcss::Commands.engines_roots

            assert_equal 2, roots.size
            assert_includes roots, engine1_css.to_s
            assert_includes roots, engine2_css.to_s
            assert_not_includes roots, engine3_css.to_s
          end
        end
      end

      spec1.verify
      spec2.verify
    end
  end

  test ".application_css creates tempfile when engines exist" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      # Create necessary files
      app_css = root.join("app/assets/tailwind/application.css")
      FileUtils.mkdir_p(File.dirname(app_css))
      FileUtils.touch(app_css)

      engine_css = root.join("app/assets/tailwind/test_engine/application.css")
      FileUtils.mkdir_p(File.dirname(engine_css))
      FileUtils.touch(engine_css)

      Rails.stub(:root, root) do
        Tailwindcss::Commands.stub(:engines_roots, [engine_css.to_s]) do
          css_path = Tailwindcss::Commands.application_css
          assert_equal css_path, Tailwindcss::Commands.class_variable_get(:@@tempfile).path

          content = File.read(css_path)
          assert_match "@import \"#{engine_css}\";", content
          assert_match "@import \"#{app_css}\";", content
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

      Rails.stub(:root, root) do
        Tailwindcss::Commands.stub(:engines_roots, []) do
          css_path = Tailwindcss::Commands.application_css
          assert_equal app_css.to_s, css_path
        end
      end
    end
  end

  test ".remove_tempfile! cleans up temporary file" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      Rails.stub(:root, root) do
        Tailwindcss::Commands.stub(:engines_roots, ["dummy_engine"]) do
          css_path = Tailwindcss::Commands.application_css
          assert File.exist?(css_path)

          Tailwindcss::Commands.remove_tempfile!
          refute File.exist?(css_path)
        end
      end
    end
  end
end
