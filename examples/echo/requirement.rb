require 'async'
require 'async/io'
require 'async/queue'
require 'async/io/trap'
require 'async/io/stream'
require 'async/io/host_endpoint'

def certificate_authority
  certificate_authority_key = OpenSSL::PKey::RSA.new(2048)
  certificate_authority_name = OpenSSL::X509::Name.parse("O=TestCA/CN=localhost")

  certificate_authority = begin
    certificate = OpenSSL::X509::Certificate.new
    certificate.subject = certificate_authority_name
    certificate.issuer = certificate_authority_name
    certificate.public_key = certificate_authority_key.public_key
    certificate.serial = 1
    certificate.version = 2 
    certificate.not_before = Time.now
    certificate.not_after = Time.now + 3600
    extension_factory = OpenSSL::X509::ExtensionFactory.new
    extension_factory.subject_certificate = certificate
    extension_factory.issuer_certificate = certificate
    certificate.add_extension extension_factory.create_extension("basicConstraints", "CA:TRUE", true)
    certificate.add_extension extension_factory.create_extension("keyUsage", "keyCertSign, cRLSign", true)
    certificate.add_extension extension_factory.create_extension("subjectKeyIdentifier", "hash")
    certificate.add_extension extension_factory.create_extension("authorityKeyIdentifier", "keyid:always", false)
    certificate.sign certificate_authority_key, OpenSSL::Digest::SHA256.new
  end

  certificate_store = begin
    OpenSSL::X509::Store.new.tap do |certificates|
      certificates.add_cert(certificate_authority)
    end
  end

  [certificate_authority_key, certificate_authority_name, certificate_authority, certificate_store]
end

def valid_certificate
  valid_certificate = begin
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
  end
end

def host_certificate
  host_certificate = begin
    keys = begin
      Hash[['127.0.0.1'].collect{|name| [name, OpenSSL::PKey::RSA.new(2048)]}]
    end
    certificates = begin
      Hash[
        ['127.0.0.1'].collect do |name|
          certificate_name = OpenSSL::X509::Name.parse("O=Test/CN=#{name}")
          certificate = OpenSSL::X509::Certificate.new
          certificate.subject = certificate_name
          certificate.issuer = certificate_authority[2].subject
          certificate.public_key = keys[name].public_key
          certificate.serial = 2
          certificate.version = 2
          certificate.not_before = Time.now
          certificate.not_after = Time.now + 3600
          extension_factory = OpenSSL::X509::ExtensionFactory.new
          extension_factory.subject_certificate = certificate
          extension_factory.issuer_certificate = certificate_authority[2]
          certificate.add_extension extension_factory.create_extension("keyUsage", "digitalSignature", true)
          certificate.add_extension extension_factory.create_extension("subjectKeyIdentifier", "hash")
          certificate.sign certificate_authority[0], OpenSSL::Digest::SHA256.new
          [name, certificate]
        end
      ]
    end

    server_context = begin
      OpenSSL::SSL::SSLContext.new.tap do |context|
        context.servername_cb = Proc.new do |socket, name|
          if ['127.0.0.1'].include? name
            socket.hostname = name
            OpenSSL::SSL::SSLContext.new.tap do |context|
              context.cert = certificates[name]
              context.key = keys[name]
            end
          end
        end
      end
    end
    client_context = begin
      OpenSSL::SSL::SSLContext.new.tap do |context|
        context.cert_store = certificate_authority[3]
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
    end
  end

  [host_certificate, server_context, client_context]
end

def config
  endpoint = Async::IO::Endpoint.tcp("127.0.0.1", 6779, reuse_port: true, timeout: 10)
  server_endpoint = Async::IO::SSLEndpoint.new(endpoint, ssl_context: host_certificate[1], timeout: 20)
  client_endpoint = Async::IO::SSLEndpoint.new(endpoint, ssl_context: host_certificate[2], timeout: 20)

  data = "The quick brown fox jumped over the lazy dog."
  [endpoint, server_endpoint, client_endpoint, data]
end
