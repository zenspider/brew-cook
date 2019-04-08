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

require "formula"
require "tab"
require "cmd/deps"
require "cask/all"

module Homebrew
  class Manifest
    attr_accessor :taps, :formulas, :casks, :noop, :verbose

    def initialize noop = false
      self.taps     = []
      self.formulas = []
      self.casks    = []
      self.noop     = noop
      self.verbose  = false
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
      if names.include? `hostname -s`.chomp then
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
        if f.include?("/") || File.exist?(f)
          Formulary.factory f
        else
          Formulary.find_with_priority f
        end
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
      }.uniq
    end

    def run cmd
      if noop then
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
      manifest = lookup_formula

      all = Formula.installed

      installed_casks = nil
      capture_io do # STFU -- complaining about handbrakecli calling license
        installed_casks = Cask::Caskroom.casks.map(&:token)
      end

      installed_taps = Tap.names

      leaves = self.leaves manifest

      deps = all - leaves

      extra    = leaves - manifest
      missing  = manifest - leaves

      flags = Hash[formulas.map { |k,*v| [k, v] }]

      deps_cur = deps_for(leaves)
      deps_new = deps_for(leaves-extra)

      deps_add = deps_new - deps_cur
      deps_rm  = deps_cur - deps_new

      casks_add = casks - installed_casks
      casks_del = installed_casks - casks

      taps_add = taps - installed_taps
      taps_del = installed_taps - taps

      if verbose then
        pp :installed
        pp all.map(&:name)
        puts
        pp :leaves
        pp leaves.map(&:name)
        puts
        pp :manifest
        pp manifest.map(&:name)
        puts
        pp :deps
        pp deps.map(&:name)
        puts
        pp :extra
        pp extra.map(&:name)
        puts
        pp :missing
        pp missing.map(&:name)
        puts
        pp :add?
        pp deps_add.map(&:name)

        puts
        pp :casks
        puts
        pp :add
        pp casks_add
        pp :del
        pp casks_del

        puts
        pp :taps
        puts
        pp :add
        pp taps_add
        pp :del
        pp taps_del
      end

      (extra + deps_rm).each do |dep|
        cmd = "brew rm #{dep}"
        run cmd
      end

      missing.each do |dep|
        # TODO? Bundle::BrewInstaller.install dep.full_name, flags[dep.full_name]
        args = (flags[dep.full_name] || []).map { |arg| "--#{arg}" }
        cmd = "brew install #{dep} #{args.join " "}"
        run cmd
      end

      casks_add.each do |cask|
        cmd = "brew cask install #{cask}"
        run cmd
      end

      casks_del.each do |cask|
        cmd = "brew cask uninstall #{cask}"
        run cmd
      end

      taps_add.each do |tap|
        cmd = "brew tap #{tap}"
        run cmd
      end

      taps_del.each do |tap|
        cmd = "brew untap #{tap}"
        run cmd
      end
    end
  end

  def self.cook
    noop = ARGV.delete("-n") # FIX: real processing
    verbose = ARGV.delete("-v")

    ENV["HOMEBREW_DEBUG"]="1" if ARGV.delete("--debug")

    path = ARGV.first || File.expand_path("~/.brew_manifest")

    abort "Please supply a Brewfile path or make a ~/.brew_manifest" unless path

    manifest = Manifest.new noop
    manifest.verbose = verbose if verbose
    manifest.instance_eval File.read(path), path
    manifest.execute
  end
end

Homebrew.cook
