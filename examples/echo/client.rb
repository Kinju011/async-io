#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require './requirement'

# endpoint = Async::IO::Endpoint.tcp('localhost', 4578)
client_context = begin
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert_store = certificate_authority[3]
      context.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
end

client_endpoint = Async::IO::SSLEndpoint.new(config, ssl_context: client_context, timeout: 20)

Async do |task|
	client_endpoint.connect do |peer|
		stream = Async::IO::Stream.new(peer)
		
		while true
			task.sleep 1
			stream.puts "Hello World!"
			puts stream.gets.inspect
		end
	end
end
