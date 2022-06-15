#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require './requirement'

def valid_certificate
  key = OpenSSL::PKey::RSA.new(2048)
  certificate_name = OpenSSL::X509::Name.parse("O=Test/CN=localhost")
  certificate = begin
    certificate = OpenSSL::X509::Certificate.new
    certificate.subject = certificate_name
    certificate.issuer = certificate_authority[2].subject
    certificate.public_key = key.public_key
    certificate.serial = 2
    certificate.version = 2
    certificate.not_before = Time.now
    certificate.not_after = Time.now + 3600
    extension_factory = OpenSSL::X509::ExtensionFactory.new()
    extension_factory.subject_certificate = certificate
    extension_factory.issuer_certificate = certificate_authority[2]
    certificate.add_extension extension_factory.create_extension("keyUsage", "digitalSignature", true)
    certificate.add_extension extension_factory.create_extension("subjectKeyIdentifier", "hash")
    certificate.sign certificate_authority[0], OpenSSL::Digest::SHA256.new
  end

  [key, certificate]
end

# endpoint = Async::IO::Endpoint.tcp('localhost', 4578)
server_context = begin
	OpenSSL::SSL::SSLContext.new.tap do |context|
	  context.cert = valid_certificate[1]
	  context.key = valid_certificate[2]
	end
end
server_endpoint = Async::IO::SSLEndpoint.new(config, ssl_context: server_context, timeout: 20)


interrupt = Async::IO::Trap.new(:INT)
ready = Async::Queue.new

Async do |top|
	interrupt.install!
	
	server_endpoint.bind do |server|
		Console.logger.info(server) {"Accepting connections on #{server.local_address.inspect}"}
		
		# task.async do |subtask|
		# 	interrupt.wait
			
		# 	Console.logger.info(server) {"Closing server socket..."}
		# 	server.close
			
		# 	interrupt.default!
			
		# 	Console.logger.info(server) {"Waiting for connections to close..."}
		# 	subtask.sleep(4)
			
		# 	Console.logger.info(server) do |buffer|
		# 		buffer.puts "Stopping all tasks..."
		# 		task.print_hierarchy(buffer)
		# 		buffer.puts "", "Reactor Hierarchy"
		# 		task.reactor.print_hierarchy(buffer)
		# 	end
			
		# 	task.stop
		# end

		ready.enqueue(server)
		server.listen(10)
		
		# server.listen(128)
		
		server.accept do |peer|
			stream = Async::IO::Stream.new(peer)
			
			while chunk = stream.read_partial
				Console.logger.debug(self) {chunk.inspect}
				stream.write(chunk)
				stream.flush
				
				Console.logger.info(server) do |buffer|
					task.reactor.print_hierarchy(buffer)
				end
			end
		end
	end
end
