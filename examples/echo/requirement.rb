require 'async'
require 'async/io'
require 'async/queue'
require 'async/io/trap'
require 'async/io/stream'
require 'async/io/ssl_endpoint'

def certificate_authority
  certificate_authority_key = OpenSSL::PKey::RSA.new(2048)
  certificate_authority_name = OpenSSL::X509::Name.parse("O=TestCA/CN=localhost")

  cert_authority = begin
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
      certificates.add_cert(cert_authority)
    end
  end

  [certificate_authority_key, certificate_authority_name, cert_authority, certificate_store]
end

def host_certificate
  host_certificate = begin
    keys = begin
      Hash[hosts.collect{|name| [name, OpenSSL::PKey::RSA.new(2048)]}]
    end
    certificates = begin
      Hash[
        hosts.collect do |name|
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
  end
end

def config
  endpoint = Async::IO::Endpoint.tcp("127.0.0.1", 6779, reuse_port: true, timeout: 10)
end
