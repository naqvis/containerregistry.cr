require "../spec_helper"
require "./remote_helper"
require "http/server"

module V1::Remote
  it "Test Index Raw Manifest" do
    idx = random_index
    expected_repo = "foo/bar"

    cases = [
      {
        name:           "normal pull, by tag",
        ref:            "latest",
        response_body:  must_raw_manifest(idx),
        content_digest: must_digest(idx).to_s,
        want_err:       false,
      }, {
        name:           "normal pull, by digest",
        ref:            must_digest(idx).to_s,
        response_body:  must_raw_manifest(idx),
        content_digest: must_digest(idx).to_s,
        want_err:       false,
      }, {
        name:           "right content-digest, wrong body, by digest",
        ref:            must_digest(idx).to_s,
        response_body:  "not even json",
        content_digest: must_digest(idx).to_s,
        want_err:       true,
      }, {
        name:           "right body, wrong content-digest, by tag",
        ref:            "latest",
        response_body:  must_raw_manifest(idx),
        content_digest: BOGUS_DIGEST,
        want_err:       false,
      }, {
        # NB: This succeeds! We don't care what the registry thinks.
        name:           "right body, wrong content-digest, by digest",
        ref:            must_digest(idx).to_s,
        response_body:  must_raw_manifest(idx),
        content_digest: BOGUS_DIGEST,
        want_err:       false,
      },
    ]
    # idx = random_index
    # expected_repo = "foo/bar"

    cases.each_with_index do |tc, i|
      V1::Logger.info "Running Test - #{tc[:name]}"
      manifest_path = "/v2/#{expected_repo}/manifests/#{tc[:ref]}"
      server = HTTP::Server.new do |ctx|
        case ctx.request.path
        when "/v2/"
          ctx.response.print "okay"
        when manifest_path
          if ctx.request.method != "GET"
            fail "Method; got #{ctx.request.method}, want 'GET'"
          end
          ctx.response.headers.add "Docker-Content-Digest", tc[:content_digest]
          content = tc[:response_body]
          content = content.is_a?(String) ? content.to_slice : content
          ctx.response.write content
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
        ref = new_reference(address.to_s, expected_repo, tc[:ref])
        rmt = RemoteIndex.new(
          fetcher: Fetcher.new(ref: ref,
            client: Cossack::Client.new)
        )
        if tc[:want_err]
          expect_raises(Exception) do
            rmt.raw_manifest
          end
        else
          rmt.raw_manifest
        end
      ensure
        server.close
      end
    end
  end

  it "Test Index" do
    idx = random_index
    expected_repo = "foo/bar"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"
    child_digest = must_index_manifest(idx).manifests[0].digest
    child = must_child(idx, child_digest)
    child_path = sprintf "/v2/%s/manifests/%s", expected_repo, child_digest.to_s
    config_path = sprintf "/v2/%s/blobs/%s", expected_repo, must_config_name(child).to_s
    manifest_req_count = 0
    child_req_count = 0

    server = HTTP::Server.new do |ctx|
      case ctx.request.path
      when "/v2/"
        ctx.response.print "okay"
      when manifest_path
        fail "Method; got #{ctx.request.method}, want 'GET'" unless ctx.request.method == "GET"
        manifest_req_count += 1
        ctx.response.content_type = must_media_type(idx).to_s
        ctx.response.write must_raw_manifest(idx)
      when child_path
        fail "Method; got #{ctx.request.method}, want 'GET'" unless ctx.request.method == "GET"
        child_req_count += 1
        ctx.response.write must_raw_manifest(child)
      when config_path
        fail "Method; got #{ctx.request.method}, want 'GET'" unless ctx.request.method == "GET"
        ctx.response.write must_raw_config_file(child)
      else
        fail "Unexpected path: #{ctx.request.path}"
      end
    end
    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield
      tag = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false
      rmt = Remote.index tag, Remote.with_transport(Cossack::Client.new)
      rmt_child = rmt.image(child_digest)

      # Test that index works as expected
      got = must_raw_manifest(rmt)
      want = must_raw_manifest(idx)
      got.should eq(want)

      got = must_index_manifest(rmt)
      want = must_index_manifest(idx)
      got.should eq(want)

      got = must_digest(rmt)
      want = must_digest(idx)
      got.should eq(want)

      # Make sure caching the manifest works for index.
      fail "raw_manifest made #{manifest_req_count} requests, expected 1" if manifest_req_count != 1

      # Test that child works as expected.
      got = must_raw_manifest(rmt_child)
      want = must_raw_manifest(child)
      got.should eq(want)

      got = must_raw_config_file(rmt_child)
      want = must_raw_config_file(child)
      got.should eq(want)

      # Make sure caching the manifest works for child.
      fail "raw_manifest made #{child_req_count} requests, expected 1" if child_req_count != 1

      # Try to fetch bogus children
      bogus_hash = must_hash(BOGUS_DIGEST)
      expect_raises(Exception) do
        rmt.image(bogus_hash)
      end
      expect_raises(Exception) do
        rmt.image_index(bogus_hash)
      end
    ensure
      server.close
    end
  end
end
