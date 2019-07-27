require "../../spec_helper"
require "http/server"
require "cossack"

module V1::Remote::Transport
  it "Test Bearer Refresh" do
    basic = Authn::Basic.new("foo", "bar")
    expected_token = "Sup3rDup3rS3cr3tz"
    expected_scope = "this-is-your-scope"
    expected_service = "my-service.io"

    server = HTTP::Server.new do |ctx|
      hdr = ctx.request.headers["Authorization"]
      if !hdr.starts_with?("Basic")
        fail "Header.Get(Authorization); got #{hdr}, want Basic prefix"
      end
      hdr.should eq(basic.authorization)
      if (query = ctx.request.query)
        params = HTTP::Params.parse query
        params["scope"].should eq(expected_scope)
        params["service"].should eq(expected_service)
      else
        fail "no query params"
      end
      ctx.response.write ::Hash{"token" => expected_token}.to_json.to_slice
    end

    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield
      reg = Name::Registry.new expected_service, strict: false
      bt = Bearer.new(
        client: Cossack::Client.new,
        basic: basic,
        registry: reg,
        realm: "http://#{address.to_s}/v2/auth",
        scopes: [expected_scope],
        service: expected_service,
        scheme: "http"
      )

      bt.refresh
    ensure
      server.close
    end
  end
end
