require "../spec_helper"
require "http/server"

module V1::Remote
  it "Test List Tags" do
    cases = [
      {
        name:          "success",
        response_body: ::Hash{"tags" => ["foo", "bar"]}.to_json,
        want_err:      false,
        want_tags:     ["foo", "bar"],
      }, {
        name:          "not json",
        response_body: "notjson",
        want_err:      true,
        want_tags:     [] of String,
      },
    ]

    repo_name = "ubuntu"
    cases.each_with_index do |tc, i|
      tags_path = sprintf "/v2/%s/tags/list", repo_name

      server = HTTP::Server.new do |ctx|
        case ctx.request.path
        when "/v2/"
          ctx.response.print "okay"
        when tags_path
          fail "Method; got #{ctx.request.method}, want 'GET'" unless ctx.request.method == "GET"
          ctx.response.write tc[:response_body].to_slice
        else
          fail "Unexpected path: #{ctx.request.path}"
        end
      end
      address = server.bind_tcp 8085 + i
      spawn do
        server.listen
      end
      begin
        Fiber.yield
        repo = Name::Repository.new sprintf("%s/%s", address.to_s, repo_name), strict: false
        if tc[:want_err]
          expect_raises(JSON::ParseException) do
            Remote.list repo, Remote.with_transport(Cossack::Client.new)
          end
        else
          tags = Remote.list repo, Remote.with_transport(Cossack::Client.new)
          tags.should eq(tc[:want_tags])
        end
      ensure
        server.close
      end
    end
  end
end
