require "net/http"
require "uri" # URI 也是明确 require 比较好

class WebhookJob < ApplicationJob
  queue_as :default

  def perform(webhook_url, event, payload)
    return unless webhook_url.present?

    begin
      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
      request.body = { event: event, payload: payload }.to_json
      response = http.request(request)

      Rails.logger.info "WebhookJob: Triggered for event '#{event}' to '#{webhook_url}'. Response: #{response.code} #{response.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      Rails.logger.error "WebhookJob: Network error triggering webhook for event '#{event}' to '#{webhook_url}': #{e.message}"
      # 可以选择重试或记录失败
      # raise e # 如果希望 SolidQueue 根据配置重试
    rescue StandardError => e
      Rails.logger.error "WebhookJob: Error triggering webhook for event '#{event}' to '#{webhook_url}': #{e.message}"
      # raise e # 如果希望 SolidQueue 根据配置重试
    end
  end
end
