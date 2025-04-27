require "io/console"


desc "Create a superuser interactively (with username, optional email, password confirmation)"
task createsuperuser: :environment do
  puts "🚀 Let's create a superuser!"

  username = nil
  email = nil
  password = nil
  password_confirmation = nil

  # 捕获 Ctrl+C，优雅退出
  Signal.trap("INT") do
    puts "\n❗ 终止创建超级用户。退出。"
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
    puts "✅ 成功创建超级用户 #{user.username}！"
  else
    puts "❌ 创建失败，原因如下："
    user.errors.full_messages.each { |msg| puts "- #{msg}" }
  end
end
