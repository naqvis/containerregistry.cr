require "../spec_helper"

module Net
  it "Test Parse IP" do
    parse_ip_tests = [
      {"127.0.1.2", ipv4(127, 0, 1, 2)},
      {"127.0.0.1", ipv4(127, 0, 0, 1)},
      {"127.001.002.003", ipv4(127, 1, 2, 3)},
      {"::ffff:127.1.2.3", ipv4(127, 1, 2, 3)},
      {"::ffff:127.001.002.003", ipv4(127, 1, 2, 3)},
      {"::ffff:7f01:0203", ipv4(127, 1, 2, 3)},
      {"0:0:0:0:0000:ffff:127.1.2.3", ipv4(127, 1, 2, 3)},
      {"0:0:0:0:000000:ffff:127.1.2.3", ipv4(127, 1, 2, 3)},
      {"0:0:0:0::ffff:127.1.2.3", ipv4(127, 1, 2, 3)},

      {"2001:4860:0:2001::68", IP[0x20, 0x01, 0x48, 0x60, 0, 0, 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0x00, 0x68]},
      {"2001:4860:0000:2001:0000:0000:0000:0068", IP[0x20, 0x01, 0x48, 0x60, 0, 0, 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0x00, 0x68]},

      {"-0.0.0.0", nil},
      {"0.-1.0.0", nil},
      {"0.0.-2.0", nil},
      {"0.0.0.-3", nil},
      {"127.0.0.256", nil},
      {"abc", nil},
      {"123:", nil},
      {"fe80::1%lo0", nil},
      {"fe80::1%911", nil},
      {"", nil},
      {"a1:a2:a3:a4::b1:b2:b3:b4", nil},
    ]
    parse_ip_tests.each_with_index do |t, _|
      ip = IP.parse t[0]
      ip.should eq(t[1])
    end
  end

  it "Test IP Mask" do
    ip_mask_test = [
      {ipv4(192, 168, 1, 127), ipv4_mask(255, 255, 255, 128), ipv4(192, 168, 1, 0)},
      {ipv4(192, 168, 1, 127), IPMask.parse("255.255.255.192"), ipv4(192, 168, 1, 64)},
      {ipv4(192, 168, 1, 127), IPMask.parse("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffe0"), ipv4(192, 168, 1, 96)},
      {ipv4(192, 168, 1, 127), ipv4_mask(255, 0, 255, 0), ipv4(192, 0, 1, 0)},
      {IP.parse("2001:db8::1"), IPMask.parse("ffff:ff80::"), IP.parse("2001:d80::")},
      {IP.parse("2001:db8::1"), IPMask.parse("f0f0:0f0f::"), IP.parse("2000:d08::")},
    ]

    ip_mask_test.each_with_index do |t, i|
      if (o = t[0])
        if (m = t[1])
          ip = o.mask(m)
          # ip.should eq(t[2])
          if ip != t[2]
            fail "#{i + 1}: IP(#{o.to_s}).mask(#{m.to_s}) = #{ip.to_s}, want #{t[2].to_s}"
          end
        else
          fail "#{i + 1} invalid mask object."
        end
      else
        fail "#{i + 1} invalid input IP."
      end
    end
  end

  it "Test IPMask String" do
    tests = [
      {ipv4_mask(255, 255, 255, 240), "fffffff0"},
      {ipv4_mask(255, 0, 128, 0), "ff008000"},
      {IPMask.parse("ffff:ff80::"), "ffffff80000000000000000000000000"},
      {IPMask.parse("ef00:ff80::cafe:0"), "ef00ff800000000000000000cafe0000"},
    ]

    tests.each_with_index do |t, i|
      if (ip = t[0])
        if ip.to_s != t[1]
          fail "#{i + 1}: IP(#{ip.to_s}), want: #{t[1]}"
        end
      end
    end
  end
end
