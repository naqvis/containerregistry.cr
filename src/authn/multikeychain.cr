require "../name/registry"
require "./authn"

module Authn
  def self.multi_keychain(*kcs : Keychain)
    multi = MultiKeychain.new
    kcs.each { |kc| multi.add kc }
    multi
  end

  # MultiKeychain composes a list of keychains into one new keychain
  private class MultiKeychain < Keychain
    @keychains : Array(Keychain)

    def initialize
      @keychains = Array(Keychain).new
    end

    def add(kc : Keychain)
      @keychains << kc
    end

    def resolve(registry : Name::Registry)
      @keychains.each do |kc|
        auth = kc.resolve(registry)
        return auth if auth != ANONYMOUS
      end
      ANONYMOUS
    end
  end
end
