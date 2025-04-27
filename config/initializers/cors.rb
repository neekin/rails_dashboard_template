Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"  # 可以换成你的前端地址
    resource "*",
      headers: :any,
      expose: [ "access-token", "refresh-token", "client", "uid" ],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
