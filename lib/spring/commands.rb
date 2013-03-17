# If the config/spring.rb contains requires for commands from other gems,
# then we need to be under bundler.
require "bundler/setup"

module Spring
  @commands = {}

  class << self
    attr_reader :commands
  end

  def self.register_command(name, klass, options = {})
    commands[name] = klass

    if options[:alias]
      commands[options[:alias]] = klass
    end
  end

  def self.command?(name)
    commands.include? name
  end

  def self.command(name)
    commands.fetch name
  end

  module Commands
    class Command
      @preloads = []

      def self.preloads
        @preloads ||= superclass.preloads.dup
      end

      def self.preloads=(val)
        @preloads = val
      end

      def preloads
        self.class.preloads
      end

      def setup
        preload_files
      end

      private

      def preload_files
        preloads.each do |file|
          begin
            require file
          rescue LoadError => e
            $stderr.puts <<-MESSAGE
The #{self.class} command tried to preload #{file} but could not find it.
You can configure what to preload in your `config/spring.rb` with:
  #{self.class}.preloads = %w(files to preload)
MESSAGE
          end
        end
      end
    end

    class Test < Command
      preloads << "test_helper"

      def env(*)
        "test"
      end

      def setup
        $LOAD_PATH.unshift "test"
        super
      end

      def call(args)
        if args.empty?
          args = ['test']
        end

        # If a spec gets required here, it will stop all the test-unit
        # tests running for some strange reason, so we need to watch
        # out for that.
        specs, ok_paths = *args.partition { |path| path =~ %r{(^|/)spec(/|$)} }
        if ! specs.empty?
          $stderr.puts "WARNING: spring test does not work on specs; skipping:"
          specs.each { |path| $stderr.puts "  #{path}" }
        end

        ARGV.replace ok_paths
        ok_paths.each do |arg|
          path = File.expand_path(arg)
          if File.directory?(path)
            Dir[File.join path, "**", "*_test.rb"].each { |f| require f }
          else
            require path
          end
        end
      end

      def description
        "Execute a Test::Unit test."
      end
    end
    Spring.register_command "test", Test.new

    class RSpec < Command
      preloads << "spec_helper"

      def env(*)
        "test"
      end

      def setup
        $LOAD_PATH.unshift "spec"
        require 'rspec/core'
        ::RSpec::Core::Runner.disable_autorun!
        super
      end

      def call(args)
        $0 = "rspec"
        ::RSpec::Core::Runner.run(args)
      end

      def description
        "Execute an RSpec spec."
      end
    end
    Spring.register_command "rspec", RSpec.new

    class Cucumber < Command
      def env(*)
        "test"
      end

      def setup
        super
        require 'cucumber'
      end

      def call(args)
        ::Cucumber::Cli::Main.execute(args)
      end

      def description
        "Execute a Cucumber feature."
      end
    end
    Spring.register_command "cucumber", Cucumber.new

    class Rake < Command
      def setup
        super
        require "rake"
      end

      def call(args)
        ARGV.replace args
        ::Rake.application.run
      end

      def description
        "Run a rake task."
      end
    end
    Spring.register_command "rake", Rake.new


    class Console < Command
      def env(tail)
        tail.first if tail.first && !tail.first.index("-")
      end

      def setup
        require "rails/commands/console"
      end

      def call(args)
        ARGV.replace args
        ::Rails::Console.start(::Rails.application)
      end

      def description
        "Start the Rails console."
      end
    end
    Spring.register_command "console", Console.new, alias: "c"

    class Generate < Command
      def setup
        super
        Rails.application.load_generators
      end

      def call(args)
        ARGV.replace args
        require "rails/commands/generate"
      end

      def description
        "Trigger a Rails generator."
      end
    end
    Spring.register_command "generate", Generate.new, alias: "g"

    class Runner < Command
      def env(tail)
        previous_option = nil
        tail.reverse.each do |option|
          case option
          when /--environment=(\w+)/ then return $1
          when '-e' then return previous_option
          end
          previous_option = option
        end
        nil
      end

      def call(args)
        Object.const_set(:APP_PATH, Rails.root.join('config/application'))
        ARGV.replace args
        require "rails/commands/runner"
      end

      def description
        "Execute a command with the Rails runner."
      end
    end
    Spring.register_command "runner", Runner.new, alias: "r"
  end

  # Load custom commands, if any.
  # needs to be at the end to allow modification of existing commands.
  config = File.expand_path("./config/spring.rb")
  require config if File.exist?(config)
end
