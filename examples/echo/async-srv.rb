require './requirement'

ready = Async::Queue.new
Async do
  config[1].bind do |server|
    ready.enqueue(server)
    server.listen(10)
    begin
      server.accept do |peer, address|
        expect(peer.timeout).to be == 10
        data = peer.read(512)
        peer.write(data)
      end
    rescue OpenSSL::SSL::SSLError
    end
  end
  ready.dequeue
end
