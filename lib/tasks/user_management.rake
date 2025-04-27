
desc "Reset a user's password"
task reset_password: :environment do
  print "Enter the username of the user whose password you want to reset: "
  username = STDIN.gets.chomp.strip

  user = User.find_by(username: username)

  if user.nil?
    puts "❗ 用户不存在，请检查用户名！"
    exit 1
  end

  print "Enter the new password (至少6位): "
  new_password = STDIN.noecho(&:gets).chomp
  puts ""

  print "Confirm the new password: "
  new_password_confirmation = STDIN.noecho(&:gets).chomp
  puts ""

  if new_password.length < 6
    puts "❗ 密码太短，请至少输入6位"
    exit 1
  end

  if new_password != new_password_confirmation
    puts "❗ 两次密码不一致，请重新输入"
    exit 1
  end

  user.password = new_password
  user.password_confirmation = new_password_confirmation

  if user.save
    puts "✅ 密码已成功重置为新密码！"
  else
    puts "❌ 密码重置失败，原因如下："
    user.errors.full_messages.each { |msg| puts "- #{msg}" }
  end
end

desc "Delete a user by username"
task delete_user: :environment do
  print "Enter the username of the user you want to delete: "
  username = STDIN.gets.chomp.strip

  user = User.find_by(username: username)

  if user.nil?
    puts "❗ 用户不存在，请检查用户名！"
    exit 1
  end

  print "Are you sure you want to delete the user #{username}? (y/n): "
  confirm = STDIN.gets.chomp.strip.downcase

  if confirm != "y"
    puts "❗ 用户删除操作已取消。"
    exit 0
  end

  if user.destroy
    puts "✅ 用户 #{username} 已成功删除！"
  else
    puts "❌ 删除失败，原因如下："
    user.errors.full_messages.each { |msg| puts "- #{msg}" }
  end
end


desc "Create a user interactively (with username, optional email, password confirmation)"
task create_user: :environment do
  puts "🚀 Let's create a user"

  username = nil
  email = nil
  password = nil
  password_confirmation = nil

  # 捕获 Ctrl+C，优雅退出
  Signal.trap("INT") do
    puts "\n❗ 终止创建用户。退出。"
    exit
  end

  # --- 输入 username ---
  loop do
    print "Username: "
    username = STDIN.gets.chomp.strip

    if username.empty?
      puts "❗ 用户名不能为空，请重新输入"
      next
    end

    if User.exists?(username: username)
      puts "❗ 这个用户名已经存在，请换一个"
      next
    end

    break
  end

  # --- 输入 email (可选) ---
  loop do
    print "Email (optional): "
    email = STDIN.gets.chomp.strip

    if email.empty?
      email = nil
      break
    end

    unless email.match?(/\A[^@\s]+@[^@\s]+\z/)
      puts "❗ 邮箱格式无效，请重新输入或留空"
      next
    end

    if User.exists?(email: email)
      puts "❗ 这个邮箱已经被使用了，请换一个"
      next
    end

    break
  end

  # --- 输入 password ---
  loop do
    print "Password (至少6位): "
    password = STDIN.noecho(&:gets).chomp
    puts ""

    print "Password confirmation: "
    password_confirmation = STDIN.noecho(&:gets).chomp
    puts ""

    if password.length < 6
      puts "❗ 密码太短，请至少输入6位"
      next
    end

    if password != password_confirmation
      puts "❗ 两次密码输入不一致，请重新输入"
      next
    end

    break
  end

  # --- 创建用户 ---
  user = User.new(
    username: username,
    email: email
  )

  user.password = password
  user.password_confirmation = password_confirmation

  if user.save
    puts "✅ 成功创建用户 #{user.username}！"
  else
    puts "❌ 创建失败，原因如下："
    user.errors.full_messages.each { |msg| puts "- #{msg}" }
  end
end
