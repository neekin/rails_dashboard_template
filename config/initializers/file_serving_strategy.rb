# 读取环境变量来决定文件服务策略，默认为 :stream (Rails send_data)
# 可选值: :stream, :redirect
strategy = ENV.fetch("FILE_SERVING_STRATEGY", "stream").downcase.to_sym

# 验证策略值
unless [ :stream, :redirect ].include?(strategy)
  Rails.logger.warn "Invalid FILE_SERVING_STRATEGY: '#{ENV['FILE_SERVING_STRATEGY']}'. Defaulting to :stream."
  strategy = :stream
end

# 设置全局配置
Rails.application.config.x.file_serving_strategy = strategy

Rails.logger.info "File serving strategy set to: #{Rails.application.config.x.file_serving_strategy}"

# 跳转到 minio的配置 不打开就是流显示
Rails.application.config.x.file_serving_strategy = :redirect
