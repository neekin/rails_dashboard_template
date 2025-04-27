import { Button } from 'antd';
import { useAuth } from '@/lib/hooks/useAuth';
export default function HomePage() {
  const { user,logout } = useAuth(); // 获取用户信息
  return (
    <div>
      <h1>Welcome to the Home Page</h1>
      <p>This is the main page of our application.</p>
      {user && <p>Welcome, {user.username}!</p>} {/* 显示用户名 */}
      <Button type="primary" onClick={logout}>
        登出
      </Button>
    </div>
  );
}