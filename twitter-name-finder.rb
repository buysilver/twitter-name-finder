#!/usr/bin/env ruby
# coding: utf-8

require 'unirest'
require 'optparse'

class Twitter
  def initialize
    @csrf_token = self.get_csrf_token
    @backoff = 0.5 # seconds to wait before hitting Twitter again
  end
  
  def get_csrf_token
    r = Unirest.get "https://twitter.com"
    r.headers[:set_cookie].each do |hdr|
      return $~[1] if (/ct0=(\w+);/ =~ hdr) != nil
    end
    raise "Unable to find CSRF token. Update the method 'get_csrf_token'."
  end  

  def available? name
    sleep @backoff
    raise "Twitter requires all names to be at least 5 characters" if name.size < 5
    r = Unirest.get "https://api.twitter.com/i/users/username_available.json?username=#{name}", headers: {"x-csrf-token" => @csrf_token}
    STDERR.puts "Unable to ask Twitter if '#{name}' is available. HTTP status code returned: #{r.code}" if r.code != 200
    case r.code
    when 200
    when 429
      @backoff *= 2
      puts "You have been hitting Twitter too hard. "\
           "Waiting #{@backoff} seconds before making a request from now on."
      self.available? name # TODO potential stack overflow
    else
      puts "HTTP status code = #{r.code}"
      raise "Unable to ask Twitter if '#{name}' is available. You probably need "\
            "to change the implementation of `available?`."
    end
    raise "Twitter gave us an unexpected response when we asked "\
          "to check the availability of '#{name}'. Update the "\
          "Twitter::available? method to the new "\
          "response schema." unless r.body.has_key? "valid"
    return r.body["valid"]
  end
end

class NameGenerator
  attr_accessor :must_start_with, :conditions

  def initialize n_chars
    @n_chars = n_chars
    @skip_until_this_name = nil
    @must_start_with = ""
    @last = -1
    @alphabet = ('a'..'z').to_a # everything must be unique!
    # `conditions` is an array of procs that take the username and determine whether to use it
    @conditions = Array.new
    @number_when_alphabet_sequence_overflows = @alphabet.size**n_chars
  end

  def alphabet= alphabet
    @alphabet = alphabet.uniq
  end

  def skip_until_this_name= skip_until_this_name
    @skip_until_this_name = skip_until_this_name
    @last = self.encode_name_to_number(skip_until_this_name)
  end

  def decode_number_to_alphabet_sequence n
=begin
The alphabet sequence is an array of characters from our alphabet.

Each username to try is identified by a number, which is here decoded to an alphabet sequence aka a string representing the name to try. This allows to easily stop and start the lengthy checking of usernames.
=end
    alphabet_size = @alphabet.size
    ret = Array.new @n_chars, @alphabet[0]
    i = @n_chars - 1
    while n > 0 and i >= 0
      ret[i] = @alphabet[n % alphabet_size]
      n /= alphabet_size
      i -= 1
    end
    ret
  end

  def encode_name_to_number name
    ret = 0
    alphabet_size = @alphabet.size
    name.chars.reverse.each_with_index do |c, pow|
      idx = @alphabet.index c
      ret += (alphabet_size**pow) * idx
    end
    ret
  end

  def current_name
    self.decode_number_to_alphabet_sequence(@last).join
  end

  def next
    @last += 1
    while @last < @number_when_alphabet_sequence_overflows \
          and not @conditions.all? {|p| p.call self.current_name}
      @last += 1
    end
    return nil if @last >= @number_when_alphabet_sequence_overflows
    self.current_name
  end
    
end

MY_VOWELS = "aeiou".split ""

def count_vowels s
  cnt = 0
  s.each_char {|c| cnt += 1 if MY_VOWELS.include? c}
  cnt
end

if ARGV.size > 0
  flags = {:prefix_str => ""}
  conditions = Array.new
  OptionParser.new do |o|
    o.banner = "Usage: ./twitter-name-finder.rb [options]"
    o.on(:REQUIRED, "--max-chars n", Integer, "Max chars in username") do |mx|
      flags[:max_chars] = mx
    end
    o.on("--min-vowels mv", Integer) do |mv|
      conditions << lambda do |username|
        count_vowels(username) >= mv
      end
    end
    o.on("--no-repeated-chars") do
      conditions << lambda do |username|
        return true if username.size < 2
        for i in 1..(username.size-1) do
          return false if username[i] == username[i-1]
        end
        true
      end
    end
    o.on("--prefix STR", String, "This string must be the first characters of the username") do |prefix_str|
      raise "You asked for a prefix string that is longer than or equal to the maximum characters you asked for. That doesn't make any sense." if prefix_str.size >= flags[:max_chars]
      flags[:prefix_str] = prefix_str
    end
    o.on("--skip-ahead-until USERNAME", String,
         "Username that the name generator will advance to before "\
         "asking Twitter. Useful when restarting from a crash.") do |s|
      flags[:skip_until_this_name] = s
    end
    o.on("-h", "--help", "Display the complete help message") do
      puts o
      exit
    end
  end.parse!
  
  twtr = Twitter.new
  ng = NameGenerator.new flags[:max_chars] - flags[:prefix_str].size
  ng.conditions = conditions
  ng.must_start_with = flags[:prefix_str]
  if flags.has_key? :skip_until_this_name
    if flags[:prefix_str].size > 0 and flags[:prefix_str] !=  flags[:skip_until_this_name].slice(0, flags[:prefix_str].size)
      puts "If you are skipping ahead until a username, "\
           "the first characters of that username must be "\
           "the same as that of the prefix string you also "\
           "provided."
      exit
    elsif flags[:prefix_str].size > 0
      ng.skip_until_this_name =
        flags[:skip_until_this_name].slice flags[:prefix_str].size..-1
    else
      ng.skip_until_this_name = flags[:skip_until_this_name]
    end
  end
  while (generated = ng.next) != nil
    name_to_try = "#{flags[:prefix_str]}#{generated}"
    # puts "trying #{name_to_try}…"
    begin
      available = twtr.available? name_to_try
      # puts "#{name_to_try} was available? #{available}"
      puts name_to_try if available
    rescue => e # TODO this is a temporary hack
      puts "Failed on #{name_to_try}"
      puts e
      redo
    end
  end
end
