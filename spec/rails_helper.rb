require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

def create_test_image
  require 'fileutils'
  fixtures_dir = Rails.root.join('spec', 'fixtures', 'files')
  FileUtils.mkdir_p(fixtures_dir)

  test_image_path = fixtures_dir.join('test_image.jpg')
  unless File.exist?(test_image_path)
    File.open(test_image_path, 'wb') do |f|
      f.write([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10,
        0x4A, 0x46, 0x49, 0x46, 0x00,
        0x01, 0x01, 0x00,
        0x00, 0x01, 0x00, 0x01,
        0x00, 0x00,
        0xFF, 0xD9
      ].pack('C*'))
    end
    puts "Created test image at #{test_image_path}"
  end
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join('spec/fixtures') ]
  config.use_transactional_fixtures = false

  config.filter_rails_from_backtrace!

  config.before(:suite) do
    create_test_image
    DatabaseCleaner.clean_with(:truncation)

    adapter = ActiveRecord::Base.connection.adapter_name.downcase
    strategy = adapter == 'sqlite' ? :truncation : :transaction
    DatabaseCleaner.strategy = strategy
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
