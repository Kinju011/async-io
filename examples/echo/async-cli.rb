require './requirement'

Async do
  config[2].connect do |client|
    client.timeout
    client.write(config[3])
    client.close_write
  end
end
