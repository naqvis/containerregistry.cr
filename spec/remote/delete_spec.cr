require "../spec_helper"
require "http/server"

module V1::Remote
  it "Test Delete" do
    expected_repo = "write/time"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"

    server = HTTP::Server.new do |ctx|
      case ctx.request.path
      when "/v2/"
        ctx.response.print "okay"
      when manifest_path
        if ctx.request.method != "DELETE"
          fail "Method; got #{ctx.request.method}, want 'DELETE'"
        end
        ctx.response.print "Deleted"
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
      delete tag, with_auth(Authn::ANONYMOUS)
    ensure
      server.close
    end
  end

  it "Test Delete Bad Status" do
    expected_repo = "write/time"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"

    server = HTTP::Server.new do |ctx|
      case ctx.request.path
      when "/v2/"
        ctx.response.print "okay"
      when manifest_path
        if ctx.request.method != "DELETE"
          fail "Method; got #{ctx.request.method}, want 'DELETE'"
        end
        ctx.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
        ctx.response.print "Boom goes server"
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
      expect_raises(Exception, "unrecognized status code during DELETE: 500; Boom goes server") do
        delete tag, with_auth(Authn::ANONYMOUS)
      end
    ensure
      server.close
    end
  end
end
