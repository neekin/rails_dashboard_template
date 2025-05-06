require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'database_cleaner/active_record'
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
    DatabaseCleaner.strategy = :truncation
  end

  # 移除重复的 before(:suite) 块

  # 使用 around 可以确保即使测试失败也会清理
  config.around(:each) do |example|
    DatabaseCleaner.start
    example.run
    DatabaseCleaner.clean
  end
end
