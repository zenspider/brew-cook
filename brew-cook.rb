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

module Homebrew
  class Manifest
    attr_accessor :taps, :formulas, :casks, :noop

    def initialize noop = false
      self.taps     = []
      self.formulas = []
      self.casks    = []
      self.noop     = noop
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
          if dep.optional? || dep.recommended?
            tab = Tab.for_formula f
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
          if dep.optional? || dep.recommended?
            tab = Tab.for_formula dependent
            Dependency.prune unless tab.with?(dep)
          elsif dep.build?
            Dependency.prune
          end
        end
      }.uniq
    end

    def execute
      # TODO: handle taps
      # TODO: handle casks
      $-w = nil # HACK
      manifest = lookup_formula

      all = Formula.installed

      leaves = self.leaves manifest

      extra    = leaves - manifest
      missing  = manifest - leaves

      flags = Hash[formulas.map { |k,*v| [k, v] }]

      deps_cur = deps_for(leaves)
      deps_new = deps_for(leaves-extra)

      # deps_add = deps_new - deps_cur
      deps_rm  = deps_cur - deps_new

      (extra + deps_rm).each do |dep|
        cmd = "brew rm #{dep}"
        if noop then
          puts cmd
        else
          system cmd
        end
      end

      missing.each do |dep|
        # TODO? Bundle::BrewInstaller.install dep.full_name, flags[dep.full_name]
        args = flags[dep.full_name].map { |arg| "--#{arg}" }
        cmd = "brew install #{dep} #{args.join " "}"
        if noop then
          puts cmd
        else
          system cmd
        end
      end
    end
  end

  def self.cook
    noop = ARGV.delete("-n") # FIX: real processing

    path = ARGV.first || File.expand_path("~/.brew_manifest")

    abort "Please supply a Brewfile path or make a ~/.brew_manifest" unless path

    manifest = Manifest.new noop
    manifest.instance_eval File.read(path), path
    manifest.execute
  end
end

Homebrew.cook
