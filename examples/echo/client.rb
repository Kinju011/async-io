#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require './requirement'

# endpoint = Async::IO::Endpoint.tcp('localhost', 4578)

Async do |task|
	config[2].connect do |peer|
		stream = Async::IO::Stream.new(peer)
		
		while true
			task.sleep 1
			# stream.puts "Hello World!"
			stream.puts config[3]
			puts stream.gets.inspect
		end
	end
end
