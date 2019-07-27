require "../../spec_helper"
require "http/server"

module V1::Remote::Transport
  it "Test Basic Transport" do
    basic = Authn::Basic.new("foo", "bar")

    server = HTTP::Server.new do |ctx|
      hdr = ctx.request.headers["Authorization"]
      if !hdr.starts_with?("Basic")
        fail "Header.Get(Authorization); got #{hdr}, want Basic prefix"
      end
      hdr.should eq(basic.authorization)
    end

    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield
      tr = Basic.new(basic, "127.0.0.1")
      tr.client.get("http://#{address.to_s}/v2/auth")
    ensure
      server.close
    end
  end
end
