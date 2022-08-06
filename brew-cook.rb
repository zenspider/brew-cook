#:  * `cook`:
#:    "Cook" a system by installing/uninstalling everything from a manifest.

# Takes a Brewfile as defined by the `brew bundle` cask. Unlike `brew
# bundle`, `brew cook` will install and _uninstall_ any needed or
# no-longer needed formulae. The manifest provided by the Brewfile is
# absolute and what should be installed at any given time.
#
# Also, unlike `brew bundle`, `brew cook` only needs you to specify
# the packages you want. All dependencies are handled automatically.
# This lets you list all the things you're interested in having,
# commenting them so you have a record as to why, and everything else
# is incidental to that manifest.

# For reference:
#
# /opt/homebrew/Library/Homebrew/formulary.rb
# /opt/homebrew/Library/Homebrew/formula.rb
# /opt/homebrew/Library/Homebrew/dependency.rb

require "formula"
require "tab"
require "cmd/deps"

module Homebrew
  class Manifest
    attr_accessor :taps, :formulas, :casks, :noop, :verbose
    attr_accessor :warned

    def initialize noop = false
      self.taps     = []
      self.formulas = []
      self.casks    = []
      self.noop     = noop
      self.verbose  = false
      self.warned   = false
    end

    def tap s
      taps << s
    end

    def brew name, args:nil
      formulas << [name, *args]
    end

    def cask name
      casks << name
    end

    def host *names
      if names.flatten.include? `hostname -s`.chomp then
        yield
      end
    end

    def leaves manifest
      installed = Formula.installed

      deps_of_installed = Set.new

      installed.each do |f|
        deps_of_installed.merge f.deps.map { |dep|
          if dep.optional? || dep.recommended? || dep.build?
            tab = Tab.for_formula f

            if verbose && tab.with?(dep) then
              p f.name => dep.name
            end

            dep.to_formula if tab.with?(dep)
          else
            dep.to_formula
          end
        }.compact
      end

      deps_of_installed.subtract manifest

      installed - deps_of_installed.to_a
    end

    def lookup_formula
      formulas.map { |f, *|
        Formulary.factory f
      }
    end

    def deps_for fs
      fs.flat_map { |f|
        f.recursive_dependencies do |dependent, dep|
          if dep.optional? || dep.recommended? || dep.build?
            tab = Tab.for_formula dependent

            if verbose && tab.with?(dep) then
              p f.name => dep.name
            end

            Dependency.prune unless tab.with?(dep)
          elsif dep.build?
            Dependency.prune
          end
        end
      }.uniq.map(&:to_formula)
    end

    def run cmd
      if noop then
        puts "# NOT executing. Run `brew cook -y` to execute:" unless warned
        self.warned = true
        puts cmd
      else
        system cmd
      end
    end

    def capture_io
      # stolen from minitest
      require "stringio"
      captured_stdout, captured_stderr = StringIO.new, StringIO.new

      orig_stdout, orig_stderr = $stdout, $stderr
      $stdout, $stderr         = captured_stdout, captured_stderr

      yield

      return captured_stdout.string, captured_stderr.string
    ensure
      $stdout = orig_stdout
      $stderr = orig_stderr
    end

    def execute
      $-w = nil # HACK
      all = Formula.installed

      installed_casks = nil
      capture_io do # STFU -- complaining about handbrakecli calling license
        installed_casks = Cask::Caskroom.casks.map(&:token)
      end

      installed_taps = Tap.names

      casks_add = casks - installed_casks
      casks_del = installed_casks - casks

      taps_add = taps - installed_taps
      taps_del = installed_taps - taps

      ## Install missing taps

      taps_add.each do |tap|
        cmd = "brew tap #{tap}"
        run cmd
      end

      ## Install missing casks

      casks_add.each do |cask|
        cmd = "brew install --cask #{cask}"
        run cmd
      end

      ## Calculate and install missing formula

      manifest = lookup_formula
      leaves   = self.leaves manifest
      deps     = all - leaves
      pkgs_rm  = leaves - manifest
      pkgs_add = manifest - leaves
      deps_cur = deps_for(leaves)
      deps_new = deps_for(leaves-pkgs_rm)
      deps_add = deps_new - deps_cur # TODO: remove?
      deps_rm  = deps_cur - deps_new - leaves

      flags = Hash[formulas.map { |k,*v| [k, v] }]
      pkgs_add.each do |dep|
        # TODO? Bundle::BrewInstaller.install dep.full_name, flags[dep.full_name]
        args = (flags[dep.full_name] || []).map { |arg| "--#{arg}" }
        cmd = "brew install #{dep} #{args.join " "}"
        run cmd
      end

      ## Remove extra pkgs

      (pkgs_rm + deps_rm).each do |dep|
        cmd = "brew rm --ignore-dependencies #{dep}"
        run cmd
      end

      ## Remove extra casks

      casks_del.each do |cask|
        cmd = "brew uninstall --cask #{cask}"
        run cmd
      end

      ## Remove extra taps

      taps_del.each do |tap|
        cmd = "brew untap #{tap}"
        run cmd
      end

      ## Debugging output

      if verbose then
        pp :installed
        pp all.map(&:name).sort
        puts
        pp :leaves
        pp leaves.map(&:name).sort
        puts
        pp :manifest
        pp manifest.map(&:name).sort
        puts
        pp :deps
        pp deps.map(&:name).sort
        puts
        pp :pkgs_rm
        pp pkgs_rm.map(&:name).sort
        puts
        pp :pkgs_add
        pp pkgs_add.map(&:name).sort
        puts
        pp :add?
        pp deps_add.map(&:name).sort

        puts
        pp :casks => { :add => casks_add, :del => casks_del }
        puts
        pp :taps => { :add => taps_add, :del => taps_del }
      end
    end

    def manifest
      formulas.map { |f, *| Formulary.factory(f).full_name } + casks
    end
  end

  def self.cook
    # FIX: real options processing
    noop    = ARGV.delete("-n") || !ARGV.delete("-y")
    verbose = ARGV.delete("-v")
    debug   = ARGV.delete("--debug")
    cmd     = ARGV.shift || "execute"

    ENV["HOMEBREW_DEBUG"]="1" if debug

    path = ARGV.first || File.expand_path("~/.brew_manifest")

    abort "Please supply a Brewfile path or make a ~/.brew_manifest" unless path

    manifest = Manifest.new noop
    manifest.verbose = verbose if verbose
    manifest.instance_eval File.read(path), path

    case cmd
    when "execute" then
      manifest.execute
    when "list" then
      puts manifest.manifest
    else
      abort "Unknown command: #{cmd}"
    end
  end
end

Homebrew.cook
