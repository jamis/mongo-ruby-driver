# frozen_string_literal: true
# rubocop:todo all

require 'lite_spec_helper'

require 'runners/connection_string'

# returns the descriptions of all specs from the given uri-options
# file name
def load_uri_options_specs_from(filename)
  path = File.join(__dir__, 'data', 'uri_options', filename)
  data = File.read(path)
  yaml = YAML.load(data)

  yaml['tests'].map { |spec| spec['description'] }
end

# Find all tests in tls-options.yml that refer to
# tlsDisableCertificateRevocationCheck and return a Hash that will be used
# by URI_SPECS_TO_SKIP to indicate that these specs should be skipped.
def tlsDisableCertificateRevocationCheck_options_tests
  load_uri_options_specs_from('tls-options.yml').
    grep(/tlsDisableCertificateRevocationCheck/).
    each_with_object({}) { |desc, hash| hash[desc] = 'Ruby driver has opted not to support tlsDisableCertificateRevocationCheck (https://jira.mongodb.org/browse/RUBY-2192)' }
end

def socks5_proxy_options_tests
  load_uri_options_specs_from('proxy-options.yml').
    each_with_object({}) { |desc, hash| hash[desc] = 'Ruby driver has opted not to implement SOCKS5 proxy (https://jira.mongodb.org/browse/RUBY-2809)' }
end

def sdam_polling_options_tests
  load_uri_options_specs_from('sdam-options.yml').
    each_with_object({}) { |desc, hash| hash[desc] = 'Ruby driver has not yet implemented https://jira.mongodb.org/browse/RUBY-3241' }
end

def single_threaded_options_tests
  load_uri_options_specs_from('single-threaded-options.yml').
    each_with_object({}) { |desc, hash| hash[desc] = 'Ruby driver is multi-threaded and does not implement single-threaded options.' }
end

URI_SPECS_TO_SKIP = {
                      # put one-off specs to skip here, in the form of:
                      # 'Test description string' => 'Reason for skipping'
                    }.
                    merge(tlsDisableCertificateRevocationCheck_options_tests).
                    merge(socks5_proxy_options_tests).
                    merge(sdam_polling_options_tests).
                    merge(single_threaded_options_tests).
                    freeze

describe 'URI options' do
  include Mongo::ConnectionString

  # Since the tests issue global assertions on Mongo::Logger,
  # we need to close all clients/stop monitoring to avoid monitoring
  # threads warning and interfering with these assertions
  clean_slate_for_all_if_possible

  skipped_specs = []
  URI_OPTIONS_TESTS.each do |file|

    spec = Mongo::ConnectionString::Spec.new(file)

    context(spec.description) do

      spec.tests.each do |test|
        context "#{test.description}" do
          skip_reason = URI_SPECS_TO_SKIP[test.description]
          if skip_reason
            skipped_specs << test.description

            before do
              skip skip_reason
            end
          end

          if test.description.downcase.include?("gssapi")
            require_mongo_kerberos
          end

          if test.valid?

            # The warning assertion needs to be first because the test caches
            # the client instance, and subsequent examples don't instantiate it
            # again.
            if test.warn?
              it 'warns' do
                expect(Mongo::Logger.logger).to receive(:warn)#.and_call_original
                expect(test.client).to be_a(Mongo::Client)
              end
            else
              it 'does not warn' do
                expect(Mongo::Logger.logger).not_to receive(:warn)
                expect(test.client).to be_a(Mongo::Client)
              end
            end

            if test.hosts
              it 'creates a client with the correct hosts' do
                expect(test.client).to have_hosts(test, test.hosts)
              end
            end

            it 'creates a client with the correct authentication properties' do
              expect(test.client).to match_auth(test)
            end

            if opts = test.expected_options
              if opts['compressors'] && opts['compressors'].include?('snappy')
                before do
                  unless ENV.fetch('BUNDLE_GEMFILE', '') =~ /snappy/
                    skip "This test requires snappy compression"
                  end
                end
              end

              if opts['compressors'] && opts['compressors'].include?('zstd')
                before do
                  unless ENV.fetch('BUNDLE_GEMFILE', '') =~ /zstd/
                    skip "This test requires zstd compression"
                  end
                end
              end

              it 'creates a client with the correct options' do
                mapped = Mongo::URI::OptionsMapper.new.ruby_to_smc(test.client.options)
                expected = Mongo::ConnectionString.adjust_expected_mongo_client_options(opts)

                expected.each do |key, expected_value|
                  expect(mapped[key]).to be == expected_value
                end
              end
            end

          else

            it 'raises an error' do
              expect{
                test.uri
              }.to raise_exception(Mongo::Error::InvalidURI)
            end
          end
        end
      end
    end
  end

  skipped_specs_not_seen = URI_SPECS_TO_SKIP.keys - skipped_specs
  if skipped_specs_not_seen.any?
    context 'URI_SPECS_TO_SKIP' do
      it 'does not include stale specs' do
        fail "the following specs do not exist any more: #{skipped_specs_not_seen.inspect}"
      end
    end
  end
end
