# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
User.destroy_all

# 创建种子数据
User.create!([
  { username: "neekin", email: "neekin@example.com", password: "password" },
  { username: "bob", email: "bob@example.com", password: "password" },
  { username: "charlie", email: "charlie@example.com", password: "password" }
])

puts "Seeded #{User.count} users."
