require "../spec_helper"
require "http/server"

module V1::Remote
  it "Test Get Schema1" do
    expected_repo = "foo/bar"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"

    server = HTTP::Server.new do |ctx|
      case ctx.request.path
      when "/v2/"
        ctx.response.print "okay"
      when manifest_path
        if ctx.request.method != "GET"
          fail "Method; got #{ctx.request.method}, want 'GET'"
        end
        ctx.response.content_type = Types::DOCKERMANIFESTSCHEMA1.to_s
        ctx.response.print "doesn't matter"
      else
        fail "Unexpected path: #{ctx.request.path}"
      end
    end
    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      tag = Name::Tag.new sprintf("%s/%s:latest", address, expected_repo), strict: false
      # Get should succeed even for invalid json. We don't parse the response.
      desc = get tag, with_auth(Authn::ANONYMOUS)

      # should fail based on media type.
      expect_raises(Exception, "unsupported media type : #{Types::DOCKERMANIFESTSCHEMA1.to_s}") do
        desc.image
      end

      # should fail based on media type.
      expect_raises(Exception, "unsupported media type : #{Types::DOCKERMANIFESTSCHEMA1.to_s}") do
        desc.image_index
      end
    ensure
      server.close
    end
  end

  it "Test Get Image As Index" do
    expected_repo = "foo/bar"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"

    server = HTTP::Server.new do |ctx|
      case ctx.request.path
      when "/v2/"
        ctx.response.print "okay"
      when manifest_path
        if ctx.request.method != "GET"
          fail "Method; got #{ctx.request.method}, want 'GET'"
        end
        ctx.response.content_type = Types::DOCKERMANIFESTSCHEMA2.to_s
        ctx.response.print "doesn't matter"
      else
        fail "Unexpected path: #{ctx.request.path}"
      end
    end
    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      tag = Name::Tag.new sprintf("%s/%s:latest", address, expected_repo), strict: false
      # Get should succeed even for invalid json. We don't parse the response.
      desc = get tag, with_auth(Authn::ANONYMOUS)

      desc.image

      # should fail based on media type.
      expect_raises(Exception, "unexpected media type for image_index: #{Types::DOCKERMANIFESTSCHEMA2.to_s}; call image instead.") do
        desc.image_index
      end
    ensure
      server.close
    end
  end
end
