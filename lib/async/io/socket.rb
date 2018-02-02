# Copyright, 2017, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'socket'
require_relative 'generic'

if RUBY_ENGINE == 'jruby'
	# We hide ClientSocket and ServerSocket behind a fascade:
	::ClientSocket = ::Socket
	::ServerSocket = ::Socket
	Object.send(:remove_const, :Socket)
	
	class Socket
		extend Forwardable
		
		Constants = ClientSocket::Constants
		include Constants
		
		def initialize(*args)
			@args = args
			@io = nil
			
			@queue = []
			@bind = nil
		end
		
		def setsockopt(*args)
			if @io
				@io.setsockopt(*args)
			else
				@queue << [:setsockopt, args]
			end
		end
		
		def io=(io)
			@io = io
			
			@queue.each do |name, args|
				@io.__send__(name, *args)
			end
		end
		
		def listen(backlog = SOMAXCONN)
			self.io ||= ServerSocket.new(*@args)
			
			@io.bind(*@bind)
			@io.listen(backlog)
		end
		
		def bind(*args)
			@bind = args
		end
		
		def connect(*args)
			self.io ||= ClientSocket.new(*@args)
			@io.bind(*@bind) if @bind
			@io.connect(*args)
		end
		
		def connect_nonblock(*args)
			self.io ||= ClientSocket.new(*@args)
			@io.connect_nonblock(*args)
		end
		
		def close
			@io.close if @io
		end
		
		def closed?
			@io.closed? if @io
		end
		
		def fileno
			@io.fileno
		end
		
		def to_io
			@io.to_io
		end
		
		attr :io
		
		def_delegators :@io, :accept, :accept_nonblock, :read_nonblock, :write_nonblock, :local_address, :remote_address, :sync
		
		def method_missing(*args)
			puts "METHOD MISSING: #{args.inspect}"
			@io.__send__(*args)
		end
	end
end

module Async
	module IO
		class BasicSocket < Generic
			wraps ::BasicSocket, :setsockopt, :connect_address, :local_address, :remote_address, :do_not_reverse_lookup, :do_not_reverse_lookup=, :shutdown, :getsockopt, :getsockname, :getpeername, :getpeereid
			
			wrap_blocking_method :recv, :recv_nonblock
			wrap_blocking_method :recvmsg, :recvmsg_nonblock
			
			wrap_blocking_method :recvfrom, :recvfrom_nonblock
			
			wrap_blocking_method :sendmsg, :sendmsg_nonblock
			wrap_blocking_method :send, :sendmsg_nonblock, invert: false
		end
		
		module ServerSocket
			def accept(task: Task.current)
				peer, address = async_send(:accept_nonblock)
				
				wrapper = Socket.new(peer, self.reactor)
				
				if block_given?
					task.async do
						task.annotate "incoming connection #{address}"
						
						begin
							yield wrapper, address
						ensure
							wrapper.close
						end
					end
				else
					return wrapper, address
				end
			end
			
			def accept_each(task: Task.current)
				task.annotate "accepting connections #{self.local_address.inspect}"
				
				while true
					self.accept(task: task) do |io, address|
						yield io, address
					end
				end
			end
		end
		
		class Socket < BasicSocket
			wraps ::Socket, :bind, :ipv6only!, :listen
			
			include ::Socket::Constants
			include ServerSocket
			
			def connect(*args)
				begin
					async_send(:connect_nonblock, *args)
				rescue Errno::EISCONN
					# We are now connected.
				end
			end
			
			def self.build(*args, task: Task.current)
				socket = wrapped_klass.new(*args)
				
				yield socket
				
				return self.new(socket, task.reactor)
			rescue Exception
				socket.close if socket
				
				raise
			end
			
			# Establish a connection to a given `remote_address`.
			# @example
			#  socket = Async::IO::Socket.connect(Async::IO::Address.tcp("8.8.8.8", 53))
			# @param remote_address [Addrinfo] The remote address to connect to.
			# @param local_address [Addrinfo] The local address to bind to before connecting.
			# @option protcol [Integer] The socket protocol to use.
			def self.connect(remote_address, local_address = nil, task: Task.current, **options)
				task.annotate "connecting to #{remote_address.inspect}"
				
				wrapper = build(remote_address.afamily, remote_address.socktype, remote_address.protocol, **options) do |socket|
					socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEADDR, true)
					
					if local_address
						socket.bind(local_address.to_sockaddr)
					end

					self.new(socket, task.reactor)
				end
				
				begin
					wrapper.connect(remote_address.to_sockaddr)
					task.annotate "connected to #{remote_address.inspect}"
				rescue
					wrapper.close
					raise
				end
				
				if block_given?
					begin
						yield wrapper, task
					ensure
						wrapper.close
					end
				else
					return wrapper
				end
			end
			
			# Bind to a local address.
			# @example
			#  socket = Async::IO::Socket.bind(Async::IO::Address.tcp("0.0.0.0", 9090))
			# @param local_address [Address] The local address to bind to.
			# @option protocol [Integer] The socket protocol to use.
			# @option reuse_port [Boolean] Allow this port to be bound in multiple processes.
			def self.bind(local_address, protocol: 0, reuse_port: false, task: Task.current, **options, &block)
				task.annotate "binding to #{local_address.inspect}"
				
				wrapper = build(local_address.afamily, local_address.socktype, protocol, **options) do |socket|
					socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEADDR, true)
					socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, true) if reuse_port
					
					socket.bind(local_address.to_sockaddr)
				end
				
				if block_given?
					begin
						yield wrapper, task
					ensure
						wrapper.close
					end
				else
					return wrapper
				end
			end
			
			# Bind to a local address and accept connections in a loop.
			def self.accept(*args, backlog: SOMAXCONN, &block)
				bind(*args) do |server, task|
					server.listen(backlog) if backlog
					
					server.accept_each(task: task, &block)
				end
			end
		end
		
		class IPSocket < BasicSocket
			wraps ::IPSocket, :addr, :peeraddr
		end
	end
end
