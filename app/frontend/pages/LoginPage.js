import React, { useState } from 'react';
import { Button, Input, Form, message } from 'antd';
import { useNavigate } from 'react-router';
import { useAuth } from '@/lib/hooks/useAuth';

const LoginPage = () => {
  const [form] = Form.useForm();
  const { login } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);

  const handleLogin = async (values) => {
    setLoading(true);
    try {
      const response = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.error || '登录失败');
      }

      const data = await response.json();
      const accessToken = response.headers.get('access-token');
      const refreshToken = response.headers.get('client');

      if (accessToken) localStorage.setItem('access-token', accessToken);
      if (refreshToken) localStorage.setItem('client', refreshToken);

      await login(data.user); // 登录成功拉取用户资料
      message.success('登录成功！');

      // 获取并跳转到登录前的页面
      const redirectPath = localStorage.getItem('redirectAfterLogin') || '/';
      localStorage.removeItem('redirectAfterLogin'); // 登录后移除路径
      navigate(redirectPath);
    } catch (err) {
      message.error(err.message || '登录失败，请稍后再试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ maxWidth: 400, margin: 'auto', paddingTop: 100 }}>
      <Form form={form} onFinish={handleLogin}>
        <Form.Item name="username" rules={[{ required: true, message: '请输入用户名' }]}>
          <Input placeholder="用户名" />
        </Form.Item>
        <Form.Item name="password" rules={[{ required: true, message: '请输入密码' }]}>
          <Input.Password placeholder="密码" />
        </Form.Item>
        <Form.Item>
          <Button type="primary" htmlType="submit" block loading={loading}>
            登录
          </Button>
        </Form.Item>
      </Form>
    </div>
  );
};

export default LoginPage;
