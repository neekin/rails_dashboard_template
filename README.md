# README



# dokku 部署

# kamal 部署


### 一些命令
rails createsuperuser #创建超级用户
rails create_user     #创建普通用户
rails reset_password  #重置密码
rails delete_user     #删除用户

RAILS_ENV=production EDITOR="code --wait" rails credentials:edit

#### 如果想在容器里使用命令
docker exec -it <container_id> bin/rails create_user