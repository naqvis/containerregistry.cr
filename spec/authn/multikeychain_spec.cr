require "../spec_helper"

module Authn
  it "Test Multikeychain" do
    one = basic("one", "secret")
    two = basic("two", "secret")
    three = basic("three", "secret")

    reg1 = Name::Registry.new "one.gcr.io", strict: true
    reg2 = Name::Registry.new "two.gcr.io", strict: true
    reg3 = Name::Registry.new "three.gcr.io", strict: true

    tests = [
      {
        # Make sure our test keychain WAI
        name: "simple fixed test (match)",
        reg:  reg1,
        kc:   FixedKeychain.new(::Hash{reg1 => one}),
        want: one,
      },
      {
        # Make sure our test keychain WAI
        name: "simple fixed test (no match)",
        reg:  reg2,
        kc:   FixedKeychain.new(::Hash{reg1 => one}),
        want: ANONYMOUS,
      },
      {
        name: "match first keychain",
        reg:  reg1,
        kc:   multi_keychain(FixedKeychain.new(::Hash{reg1 => one}),
          FixedKeychain.new(::Hash{reg1 => three, reg2 => two})),
        want: one,
      },
      {
        name: "match second keychain",
        reg:  reg2,
        kc:   multi_keychain(FixedKeychain.new(::Hash{reg1 => one}),
          FixedKeychain.new(::Hash{reg1 => three, reg2 => two})),
        want: two,
      },
      {
        name: "match no keychain",
        reg:  reg3,
        kc:   multi_keychain(FixedKeychain.new(::Hash{reg1 => one}),
          FixedKeychain.new(::Hash{reg1 => three, reg2 => two})),
        want: ANONYMOUS,
      },
    ]

    tests.each do |tc|
      V1::Logger.info "Running Test - #{tc[:name]}"
      got = tc[:kc].resolve tc[:reg]
      fail "resolve() = #{got}, wanted #{tc[:want]}" if got != tc[:want]
    end
  end

  def self.basic(u, p)
    Basic.new(u, p).as(Authenticator)
  end

  private class FixedKeychain < Keychain
    @kc : ::Hash(Name::Registry, Authenticator)

    def initialize
      @kc = Hash(Name::Registry, Authenticator).new
    end

    def initialize(@kc)
    end

    def resolve(reg : Name::Registry)
      return ANONYMOUS unless @kc.has_key?(reg)
      @kc[reg]
    end
  end
end
