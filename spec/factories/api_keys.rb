FactoryBot.define do
  factory :api_key do
    apikey { "MyString" }
    apisecret { "MyString" }
    app_entity { nil }
  end
end
