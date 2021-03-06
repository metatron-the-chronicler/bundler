# frozen_string_literal: true
require "spec_helper"

describe "bundle exec" do
  before :each do
    system_gems "rack-1.0.0", "rack-0.9.1"
  end

  it "activates the correct gem" do
    gemfile <<-G
      gem "rack", "0.9.1"
    G

    bundle "exec rackup"
    expect(out).to eq("0.9.1")
  end

  it "works when the bins are in ~/.bundle" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec rackup"
    expect(out).to eq("1.0.0")
  end

  it "works when running from a random directory" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec 'cd #{tmp("gems")} && rackup'"

    expect(out).to include("1.0.0")
  end

  it "works when exec'ing something else" do
    install_gemfile 'gem "rack"'
    bundle "exec echo exec"
    expect(out).to eq("exec")
  end

  it "works when exec'ing to ruby" do
    install_gemfile 'gem "rack"'
    bundle "exec ruby -e 'puts %{hi}'"
    expect(out).to eq("hi")
  end

  it "accepts --verbose" do
    install_gemfile 'gem "rack"'
    bundle "exec --verbose echo foobar"
    expect(out).to eq("foobar")
  end

  it "passes --verbose to command if it is given after the command" do
    install_gemfile 'gem "rack"'
    bundle "exec echo --verbose"
    expect(out).to eq("--verbose")
  end

  it "handles --keep-file-descriptors" do
    require "tempfile"

    bundle_bin = File.expand_path("../../../exe/bundle", __FILE__)

    command = Tempfile.new("io-test")
    command.sync = true
    command.write <<-G
      if ARGV[0]
        IO.for_fd(ARGV[0].to_i)
      else
        require 'tempfile'
        io = Tempfile.new("io-test-fd")
        args = %W[#{Gem.ruby} -I#{lib} #{bundle_bin} exec --keep-file-descriptors #{Gem.ruby} #{command.path} \#{io.to_i}]
        args << { io.to_i => io } if RUBY_VERSION >= "2.0"
        exec(*args)
      end
    G

    install_gemfile ""
    sys_exec("#{Gem.ruby} #{command.path}")

    if Bundler.current_ruby.ruby_2?
      expect(out).to eq("")
    else
      expect(out).to eq("Ruby version #{RUBY_VERSION} defaults to keeping non-standard file descriptors on Kernel#exec.")
    end

    expect(err).to lack_errors
  end

  it "accepts --keep-file-descriptors" do
    install_gemfile ""
    bundle "exec --keep-file-descriptors echo foobar"

    expect(err).to lack_errors
  end

  it "can run a command named --verbose" do
    install_gemfile 'gem "rack"'
    File.open("--verbose", "w") do |f|
      f.puts "#!/bin/sh"
      f.puts "echo foobar"
    end
    File.chmod(0o744, "--verbose")
    with_path_as(".") do
      bundle "exec -- --verbose"
    end
    expect(out).to eq("foobar")
  end

  it "handles different versions in different bundles" do
    build_repo2 do
      build_gem "rack_two", "1.0.0" do |s|
        s.executables = "rackup"
      end
    end

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", "0.9.1"
    G

    Dir.chdir bundled_app2 do
      install_gemfile bundled_app2("Gemfile"), <<-G
        source "file://#{gem_repo2}"
        gem "rack_two", "1.0.0"
      G
    end

    bundle! "exec rackup"

    expect(out).to eq("0.9.1")

    Dir.chdir bundled_app2 do
      bundle! "exec rackup"
      expect(out).to eq("1.0.0")
    end
  end

  it "handles gems installed with --without" do
    install_gemfile <<-G, :without => :middleware
      source "file://#{gem_repo1}"
      gem "rack" # rack 0.9.1 and 1.0 exist

      group :middleware do
        gem "rack_middleware" # rack_middleware depends on rack 0.9.1
      end
    G

    bundle "exec rackup"

    expect(out).to eq("0.9.1")
    expect(the_bundle).not_to include_gems "rack_middleware 1.0"
  end

  it "does not duplicate already exec'ed RUBYOPT" do
    install_gemfile <<-G
      gem "rack"
    G

    rubyopt = ENV["RUBYOPT"]
    rubyopt = "-rbundler/setup #{rubyopt}"

    bundle "exec 'echo $RUBYOPT'"
    expect(out).to have_rubyopts(rubyopt)

    bundle "exec 'echo $RUBYOPT'", :env => { "RUBYOPT" => rubyopt }
    expect(out).to have_rubyopts(rubyopt)
  end

  it "does not duplicate already exec'ed RUBYLIB" do
    install_gemfile <<-G
      gem "rack"
    G

    rubylib = ENV["RUBYLIB"]
    rubylib = "#{rubylib}".split(File::PATH_SEPARATOR).unshift "#{bundler_path}"
    rubylib = rubylib.uniq.join(File::PATH_SEPARATOR)

    bundle "exec 'echo $RUBYLIB'"
    expect(out).to include(rubylib)

    bundle "exec 'echo $RUBYLIB'", :env => { "RUBYLIB" => rubylib }
    expect(out).to include(rubylib)
  end

  it "errors nicely when the argument doesn't exist" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec foobarbaz"
    expect(exitstatus).to eq(127) if exitstatus
    expect(out).to include("bundler: command not found: foobarbaz")
    expect(out).to include("Install missing gem executables with `bundle install`")
  end

  it "errors nicely when the argument is not executable" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec touch foo"
    bundle "exec ./foo"
    expect(exitstatus).to eq(126) if exitstatus
    expect(out).to include("bundler: not executable: ./foo")
  end

  it "errors nicely when no arguments are passed" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec"
    expect(exitstatus).to eq(128) if exitstatus
    expect(out).to include("bundler: exec needs a command to run")
  end

  describe "with help flags" do
    each_prefix = proc do |string, &blk|
      1.upto(string.length) {|l| blk.call(string[0, l]) }
    end
    each_prefix.call("exec") do |exec|
      describe "when #{exec} is used" do
        before(:each) do
          install_gemfile <<-G
            gem "rack"
          G

          create_file("print_args", <<-'RUBY')
            #!/usr/bin/env ruby
            puts "args: #{ARGV.inspect}"
          RUBY
          bundled_app("print_args").chmod(0o755)
        end

        it "shows executable's man page when --help is after the executable" do
          bundle "#{exec} print_args --help"
          expect(out).to eq('args: ["--help"]')
        end

        it "shows executable's man page when --help is after the executable and an argument" do
          bundle "#{exec} print_args foo --help"
          expect(out).to eq('args: ["foo", "--help"]')

          bundle "#{exec} print_args foo bar --help"
          expect(out).to eq('args: ["foo", "bar", "--help"]')

          bundle "#{exec} print_args foo --help bar"
          expect(out).to eq('args: ["foo", "--help", "bar"]')
        end

        it "shows executable's man page when the executable has a -" do
          FileUtils.mv(bundled_app("print_args"), bundled_app("docker-template"))
          bundle "#{exec} docker-template build discourse --help"
          expect(out).to eq('args: ["build", "discourse", "--help"]')
        end

        it "shows executable's man page when --help is after another flag" do
          bundle "#{exec} print_args --bar --help"
          expect(out).to eq('args: ["--bar", "--help"]')
        end

        it "uses executable's original behavior for -h" do
          bundle "#{exec} print_args -h"
          expect(out).to eq('args: ["-h"]')
        end

        it "shows bundle-exec's man page when --help is between exec and the executable" do
          with_fake_man do
            bundle "#{exec} --help cat"
          end
          expect(out).to include(%(["#{root}/lib/bundler/man/bundle-exec"]))
        end

        it "shows bundle-exec's man page when --help is before exec" do
          with_fake_man do
            bundle "--help #{exec}"
          end
          expect(out).to include(%(["#{root}/lib/bundler/man/bundle-exec"]))
        end

        it "shows bundle-exec's man page when -h is before exec" do
          with_fake_man do
            bundle "-h #{exec}"
          end
          expect(out).to include(%(["#{root}/lib/bundler/man/bundle-exec"]))
        end

        it "shows bundle-exec's man page when --help is after exec" do
          with_fake_man do
            bundle "#{exec} --help"
          end
          expect(out).to include(%(["#{root}/lib/bundler/man/bundle-exec"]))
        end

        it "shows bundle-exec's man page when -h is after exec" do
          with_fake_man do
            bundle "#{exec} -h"
          end
          expect(out).to include(%(["#{root}/lib/bundler/man/bundle-exec"]))
        end
      end
    end
  end

  describe "with gem executables" do
    describe "run from a random directory" do
      before(:each) do
        install_gemfile <<-G
          gem "rack"
        G
      end

      it "works when unlocked" do
        bundle "exec 'cd #{tmp("gems")} && rackup'"
        expect(out).to eq("1.0.0")
        expect(out).to include("1.0.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec 'cd #{tmp("gems")} && rackup'"
        expect(out).to include("1.0.0")
      end
    end

    describe "from gems bundled via :path" do
      before(:each) do
        build_lib "fizz", :path => home("fizz") do |s|
          s.executables = "fizz"
        end

        install_gemfile <<-G
          gem "fizz", :path => "#{File.expand_path(home("fizz"))}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked

        bundle "exec fizz"
        expect(out).to eq("1.0")
      end
    end

    describe "from gems bundled via :git" do
      before(:each) do
        build_git "fizz_git" do |s|
          s.executables = "fizz_git"
        end

        install_gemfile <<-G
          gem "fizz_git", :git => "#{lib_path("fizz_git-1.0")}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz_git"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec fizz_git"
        expect(out).to eq("1.0")
      end
    end

    describe "from gems bundled via :git with no gemspec" do
      before(:each) do
        build_git "fizz_no_gemspec", :gemspec => false do |s|
          s.executables = "fizz_no_gemspec"
        end

        install_gemfile <<-G
          gem "fizz_no_gemspec", "1.0", :git => "#{lib_path("fizz_no_gemspec-1.0")}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz_no_gemspec"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec fizz_no_gemspec"
        expect(out).to eq("1.0")
      end
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", "0.9.1"
      gem "foo"
    G

    bundle "config auto_install 1"
    bundle "exec rackup"
    expect(out).to include("Installing foo 1.0")
  end

  describe "with gems bundled via :path with invalid gemspecs" do
    it "outputs the gemspec validation errors", :rubygems => ">= 1.7.2" do
      build_lib "foo"

      gemspec = lib_path("foo-1.0").join("foo.gemspec").to_s
      File.open(gemspec, "w") do |f|
        f.write <<-G
          Gem::Specification.new do |s|
            s.name    = 'foo'
            s.version = '1.0'
            s.summary = 'TODO: Add summary'
            s.authors = 'Me'
          end
        G
      end

      install_gemfile <<-G
        gem "foo", :path => "#{lib_path("foo-1.0")}"
      G

      bundle "exec irb"

      expect(err).to match("The gemspec at #{lib_path("foo-1.0").join("foo.gemspec")} is not valid")
      expect(err).to match('"TODO" is not a summary')
    end
  end

  describe "with gems bundled for deployment" do
    it "works when calling bundler from another script" do
      gemfile <<-G
      module Monkey
        def bin_path(a,b,c)
          raise Gem::GemNotFoundException.new('Fail')
        end
      end
      Bundler.rubygems.extend(Monkey)
      G
      bundle "install --deployment"
      bundle "exec ruby -e '`../../exe/bundler -v`; puts $?.success?'"
      expect(out).to match("true")
    end
  end

  context "`load`ing a ruby file instead of `exec`ing" do
    let(:path) { bundled_app("ruby_executable") }
    let(:shebang) { "#!/usr/bin/env ruby" }
    let(:executable) { <<-RUBY.gsub(/^ */, "").strip }
      #{shebang}

      require "rack"
      puts "EXEC: \#{caller.grep(/load/).empty? ? 'exec' : 'load'}"
      puts "ARGS: \#{$0} \#{ARGV.join(' ')}"
      puts "RACK: \#{RACK}"
    RUBY

    before do
      path.open("w") {|f| f << executable }
      path.chmod(0o755)

      install_gemfile <<-G
        gem "rack"
      G
    end

    let(:exec) { "EXEC: load" }
    let(:args) { "ARGS: #{path} arg1 arg2" }
    let(:rack) { "RACK: 1.0.0" }
    let(:exit_code) { 0 }
    let(:expected) { [exec, args, rack].join("\n") }
    let(:expected_err) { "" }

    subject { bundle "exec #{path} arg1 arg2" }

    shared_examples_for "it runs" do
      it "like a normally executed executable" do
        subject
        expect(exitstatus).to eq(exit_code) if exitstatus
        expect(err).to eq(expected_err)
        expect(out).to eq(expected)
      end
    end

    it_behaves_like "it runs"

    context "the executable exits explicitly" do
      let(:executable) { super() << "\nexit #{exit_code}\nputs 'POST_EXIT'\n" }

      context "with exit 0" do
        it_behaves_like "it runs"
      end

      context "with exit 99" do
        let(:exit_code) { 99 }
        it_behaves_like "it runs"
      end
    end

    context "the executable raises" do
      let(:executable) { super() << "\nraise 'ERROR'" }
      let(:exit_code) { 1 }
      let(:expected) { super() << "\nbundler: failed to load command: #{path} (#{path})" }
      let(:expected_err) do
        "RuntimeError: ERROR\n  #{path}:7" +
          (Bundler.current_ruby.ruby_18? ? "" : ":in `<top (required)>'")
      end
      it_behaves_like "it runs"
    end

    context "when the file uses the current ruby shebang" do
      let(:shebang) { "#!#{Gem.ruby}" }
      it_behaves_like "it runs"
    end

    context "when Bundler.setup fails" do
      before do
        gemfile <<-G
          gem 'rack', '2'
        G
        ENV["BUNDLER_FORCE_TTY"] = "true"
      end

      let(:exit_code) { Bundler::GemNotFound.new.status_code }
      let(:expected) { <<-EOS.strip }
\e[31mCould not find gem 'rack (= 2)' in any of the gem sources listed in your Gemfile or available on this machine.\e[0m
\e[33mRun `bundle install` to install missing gems.\e[0m
      EOS

      it_behaves_like "it runs"
    end

    context "when the executable exits non-zero via at_exit" do
      let(:executable) { super() + "\n\nat_exit { $! ? raise($!) : exit(1) }" }
      let(:exit_code) { 1 }

      it_behaves_like "it runs"
    end

    context "signals being trapped by bundler" do
      let(:executable) { strip_whitespace <<-RUBY }
        #{shebang}
        begin
          Thread.new do
            puts 'Started' # For process sync
            STDOUT.flush
            sleep 1 # ignore quality_spec
            raise "Didn't receive INT at all"
          end.join
        rescue Interrupt
          puts "foo"
        end
      RUBY

      it "receives the signal" do
        skip "popen3 doesn't provide a way to get pid " unless RUBY_VERSION >= "1.9.3"

        bundle("exec #{path}") do |_, o, thr|
          o.gets # Consumes 'Started' and ensures that thread has started
          Process.kill("INT", thr.pid)
        end

        expect(out).to eq("foo")
      end
    end
  end
end
