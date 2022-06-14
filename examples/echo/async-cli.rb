require './requirement'

Async do
  config[2].connect do |client|
    client.timeout
    client.write(data)
    client.close_write
  end
end
