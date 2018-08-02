require_relative "twitter-name-finder"
require "test/unit"

class TestNameGenerator < Test::Unit::TestCase
  def setup
    @s = "thisisatest"
    @ng = NameGenerator.new @s.size
  end
  
  def test_simple
    encoded = @ng.encode_name_to_number @s
    decoded = @ng.decode_number_to_alphabet_sequence(encoded).join
    assert_equal @s, decoded
  end
end
